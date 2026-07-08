const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const defaultDb = require("../db");

const PLACEHOLDER = "REEMPLAZAR_PROMPT_EJECUTIVO";
const OUTPUT_TAIL_LIMIT = 2000;
const DEFAULT_KILL_GRACE_MS = 5000;
const PASSTHROUGH_ENV_KEYS = [
  "PATH",
  "HOME",
  "TMPDIR",
  "TEMP",
  "TMP",
  "OPENCODE_MODEL",
  "OPENAI_API_KEY",
  "ANTHROPIC_API_KEY",
  "ZHIPU_API_KEY",
  "GOOGLE_API_KEY",
  "GOOGLE_GENERATIVE_AI_API_KEY",
  "GEMINI_API_KEY",
];

function truncateTail(value, maxLength = OUTPUT_TAIL_LIMIT) {
  const text = String(value || "");
  if (text.length <= maxLength) {
    return text;
  }
  return text.slice(text.length - maxLength);
}

function isPromptReady(prompt) {
  return Boolean(prompt && prompt.trim() && !prompt.includes(PLACEHOLDER));
}

function buildOpencodeEnv(sourceEnv = process.env) {
  const env = {};
  for (const key of PASSTHROUGH_ENV_KEYS) {
    if (sourceEnv[key] !== undefined) {
      env[key] = sourceEnv[key];
    }
  }
  for (const [key, value] of Object.entries(sourceEnv)) {
    if (value === undefined) continue;
    if (key.startsWith("OPENCODE_") || key.startsWith("BITFROST_")) {
      env[key] = value;
    }
  }
  return env;
}

function findPdf(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const nested = findPdf(entryPath);
      if (nested) {
        return nested;
      }
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".pdf")) {
      return entryPath;
    }
  }
  return null;
}

function runOpencode({ id, workDir, prompt, env, timeoutMs, killGraceMs }) {
  return new Promise((resolve) => {
    const model = env.OPENCODE_MODEL;
    const startedAt = Date.now();
    const tag = `[opencode pdf:${id}]`;
    console.log(`${tag} iniciando modelo=${model} timeout=${timeoutMs}ms workDir=${workDir}`);
    const child = spawn(
      "opencode",
      ["run", "--auto", "--model", model, "--dir", workDir, "--format", "json", prompt],
      { cwd: workDir, env }
    );
    console.log(`${tag} pid=${child.pid}`);
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;
    let killTimer;

    function resolveOnce(result) {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      clearTimeout(killTimer);
      resolve(result);
    }

    const timer = setTimeout(() => {
      timedOut = true;
      console.error(`${tag} timeout (${timeoutMs}ms) alcanzado, enviando SIGTERM al pid=${child.pid}`);
      child.kill("SIGTERM");
      killTimer = setTimeout(() => {
        console.error(`${tag} pid=${child.pid} no termino tras SIGTERM, enviando SIGKILL`);
        child.kill("SIGKILL");
        resolveOnce({ code: null, stdout, stderr, timedOut });
      }, killGraceMs);
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      stdout = truncateTail(stdout + text);
      process.stdout.write(`${tag} ${text}`);
    });
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr = truncateTail(stderr + text);
      process.stderr.write(`${tag} ${text}`);
    });
    child.on("error", (error) => {
      console.error(`${tag} fallo al lanzar el proceso: ${error.message}`);
      resolveOnce({ code: null, stdout, stderr: truncateTail(`${stderr}\n${error.message}`), timedOut });
    });
    child.on("close", (code) => {
      const elapsedMs = Date.now() - startedAt;
      console.log(`${tag} finalizo code=${code} transcurrido=${elapsedMs}ms${timedOut ? " (timeout)" : ""}`);
      resolveOnce({ code, stdout, stderr, timedOut });
    });
  });
}

function createPdfGenerator(options = {}) {
  const db = options.db || defaultDb;
  const dataDir = options.dataDir || path.join(__dirname, "..", "..", "data");
  const promptPath = options.promptPath || path.join(__dirname, "..", "..", "prompts", "reporte_ejecutivo.txt");
  const opencodeConfigPath = options.opencodeConfigPath || path.join(__dirname, "..", "..", "opencode.json");
  const env = buildOpencodeEnv(options.env || process.env);
  const timeoutMs = options.timeoutMs || Number(env.OPENCODE_TIMEOUT_MS) || 10 * 60 * 1000;
  const killGraceMs = options.killGraceMs || DEFAULT_KILL_GRACE_MS;
  const queuedIds = new Set();
  const queue = [];
  let running = false;
  let drainPromise = Promise.resolve();

  const getReporte = db.prepare(
    "SELECT id, reporte_sistema, reporte_red, reporte_logs, pdf_status FROM reportes WHERE id = ?"
  );
  const markGenerating = db.prepare(
    "UPDATE reportes SET pdf_status = 'generando', pdf_error = NULL WHERE id = ?"
  );
  const markReady = db.prepare(
    "UPDATE reportes SET pdf_path = ?, pdf_status = 'listo', pdf_error = NULL WHERE id = ?"
  );
  const markError = db.prepare(
    "UPDATE reportes SET pdf_path = NULL, pdf_status = 'error', pdf_error = ? WHERE id = ?"
  );

  async function processReport(id) {
    const tmpRoot = path.join(dataDir, "tmp");
    const pdfDir = path.join(dataDir, "pdfs");
    let workDir;

    try {
      const row = getReporte.get(id);
      if (!row) {
        throw new Error(`Reporte ${id} no existe`);
      }

      if (!fs.existsSync(promptPath)) {
        throw new Error("El prompt para generar el PDF no existe o no esta configurado");
      }

      const prompt = fs.readFileSync(promptPath, "utf8");
      if (!isPromptReady(prompt)) {
        throw new Error("El prompt para generar el PDF no esta configurado");
      }

      if (!env.OPENCODE_MODEL || !env.OPENCODE_MODEL.trim()) {
        throw new Error("Falta configurar OPENCODE_MODEL en el entorno");
      }

      fs.mkdirSync(tmpRoot, { recursive: true });
      fs.mkdirSync(pdfDir, { recursive: true });
      workDir = fs.mkdtempSync(path.join(tmpRoot, `${id}-`));
      fs.writeFileSync(path.join(workDir, "reporte_sistema.txt"), row.reporte_sistema || "");
      fs.writeFileSync(path.join(workDir, "reporte_red.txt"), row.reporte_red || "");
      fs.writeFileSync(path.join(workDir, "reporte_logs.txt"), row.reporte_logs || "");

      if (fs.existsSync(opencodeConfigPath)) {
        fs.copyFileSync(opencodeConfigPath, path.join(workDir, "opencode.json"));
      }

      const result = await runOpencode({ id, workDir, prompt, env, timeoutMs, killGraceMs });
      const generatedPdf = findPdf(workDir);
      if (result.code !== 0 || !generatedPdf) {
        if (result.timedOut) {
          const tail = truncateTail([result.stderr, result.stdout].filter(Boolean).join("\n"));
          throw new Error(
            tail
              ? `opencode excedio el tiempo limite (${timeoutMs}ms). Ultima salida del proceso:\n${tail}`
              : `opencode excedio el tiempo limite (${timeoutMs}ms) sin producir salida`
          );
        }
        const details = truncateTail([result.stderr, result.stdout].filter(Boolean).join("\n"));
        throw new Error(details || "opencode no genero un PDF");
      }

      const fileName = `${id}.pdf`;
      fs.renameSync(generatedPdf, path.join(pdfDir, fileName));
      markReady.run(fileName, id);
    } catch (error) {
      markError.run(truncateTail(error.message), id);
    } finally {
      if (workDir) {
        fs.rmSync(workDir, { recursive: true, force: true });
      }
    }
  }

  async function processQueue() {
    if (running) {
      return;
    }
    running = true;
    while (queue.length > 0) {
      const id = queue.shift();
      try {
        await processReport(id);
      } finally {
        queuedIds.delete(id);
      }
    }
    running = false;
  }

  function encolarGeneracion(id) {
    const row = getReporte.get(id);
    if (!row || row.pdf_status === "generando" || queuedIds.has(id)) {
      return false;
    }
    markGenerating.run(id);
    queuedIds.add(id);
    queue.push(id);
    drainPromise = drainPromise.then(processQueue);
    return true;
  }

  function drain() {
    return drainPromise;
  }

  return { encolarGeneracion, drain };
}

const defaultGenerator = createPdfGenerator();

module.exports = {
  createPdfGenerator,
  buildOpencodeEnv,
  encolarGeneracion: defaultGenerator.encolarGeneracion,
  isPromptReady,
  truncateTail,
};
