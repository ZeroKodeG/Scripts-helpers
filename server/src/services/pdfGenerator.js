const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const defaultDb = require("../db");
const { buildReportDateContext } = require("../reportTime");
const { validateNormalizedReport } = require("./reportSchema");
const { runRenderer } = require("./reportRenderer");

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
  "ZAI_API_KEY",
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

function createEmptyUsageMetrics() {
  return {
    input: 0,
    output: 0,
    reasoning: 0,
    total: 0,
    cacheRead: 0,
    cacheWrite: 0,
    cost: 0,
  };
}

function addNumber(target, key, value) {
  const numeric = Number(value);
  if (Number.isFinite(numeric)) {
    target[key] += numeric;
  }
}

function accumulateUsageFromEvent(metrics, event) {
  if (!event || event.type !== "step_finish" || !event.part) {
    return;
  }

  const tokens = event.part.tokens || {};
  const cache = tokens.cache || {};
  addNumber(metrics, "input", tokens.input);
  addNumber(metrics, "output", tokens.output);
  addNumber(metrics, "reasoning", tokens.reasoning);
  addNumber(metrics, "total", tokens.total);
  addNumber(metrics, "cacheRead", cache.read);
  addNumber(metrics, "cacheWrite", cache.write);
  addNumber(metrics, "cost", event.part.cost);
}

function consumeJsonLines(buffer, onLine) {
  let pending = buffer;
  let lineBreak = pending.indexOf("\n");
  while (lineBreak >= 0) {
    const line = pending.slice(0, lineBreak).trim();
    if (line) {
      onLine(line);
    }
    pending = pending.slice(lineBreak + 1);
    lineBreak = pending.indexOf("\n");
  }
  return pending;
}

function parseUsageMetricsFromLine(metrics, line) {
  try {
    const event = JSON.parse(line);
    accumulateUsageFromEvent(metrics, event);
  } catch {
    // Ignorar lineas que no sean JSON valido de eventos.
  }
}

function usageMetricsToDbRow(metrics = createEmptyUsageMetrics()) {
  return {
    pdf_tokens_input: metrics.input,
    pdf_tokens_output: metrics.output,
    pdf_tokens_reasoning: metrics.reasoning,
    pdf_tokens_total: metrics.total,
    pdf_tokens_cache_read: metrics.cacheRead,
    pdf_tokens_cache_write: metrics.cacheWrite,
    pdf_cost_total: Number(metrics.cost.toFixed(6)),
  };
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

function readNormalizedReport(workDir) {
  const normalizedPath = path.join(workDir, "reporte_normalizado.json");
  if (!fs.existsSync(normalizedPath)) {
    throw new Error("opencode no genero reporte_normalizado.json");
  }

  let normalized;
  try {
    normalized = JSON.parse(fs.readFileSync(normalizedPath, "utf8"));
  } catch (error) {
    throw new Error(`reporte_normalizado.json invalido: ${error.message}`);
  }

  validateNormalizedReport(normalized);
  return { normalized, normalizedPath };
}

function runOpencode({ id, workDir, prompt, env, timeoutMs, killGraceMs }) {
  return new Promise((resolve) => {
    const model = env.OPENCODE_MODEL;
    const startedAt = Date.now();
    const tag = `[opencode pdf:${id}]`;
    console.log(`${tag} iniciando modelo=${model} timeout=${timeoutMs}ms workDir=${workDir}`);
    const childEnv = { ...env, OPENCODE_CONFIG_DIR: workDir };
    const child = spawn(
      "opencode",
      ["run", "--auto", "--model", model, "--dir", workDir, "--format", "json", prompt],
      { cwd: workDir, env: childEnv, stdio: ["ignore", "pipe", "pipe"] }
    );
    console.log(`${tag} pid=${child.pid}`);
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;
    let killTimer;
    let stdoutJsonBuffer = "";
    let stderrJsonBuffer = "";
    const usageMetrics = createEmptyUsageMetrics();

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
      stdoutJsonBuffer = consumeJsonLines(stdoutJsonBuffer + text, (line) =>
        parseUsageMetricsFromLine(usageMetrics, line)
      );
      process.stdout.write(`${tag} ${text}`);
    });
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr = truncateTail(stderr + text);
      stderrJsonBuffer = consumeJsonLines(stderrJsonBuffer + text, (line) =>
        parseUsageMetricsFromLine(usageMetrics, line)
      );
      process.stderr.write(`${tag} ${text}`);
    });
    child.on("error", (error) => {
      console.error(`${tag} fallo al lanzar el proceso: ${error.message}`);
      resolveOnce({
        code: null,
        stdout,
        stderr: truncateTail(`${stderr}\n${error.message}`),
        timedOut,
        usageMetrics,
      });
    });
    child.on("close", (code) => {
      const elapsedMs = Date.now() - startedAt;
      console.log(
        `${tag} finalizo code=${code} transcurrido=${elapsedMs}ms${timedOut ? " (timeout)" : ""}`
      );
      resolveOnce({ code, stdout, stderr, timedOut, usageMetrics });
    });
  });
}

/** Adapter async sobre el pool pg (o un store de tests con los mismos metodos). */
function createPgStore(db) {
  if (db && typeof db.getReporte === "function") {
    return db;
  }

  return {
    async getReporte(id) {
      return db.queryOne(
        `SELECT id, equipo, fecha_hora, reporte_sistema, reporte_red, reporte_logs, pdf_status
         FROM reportes WHERE id = $1`,
        [id]
      );
    },
    async markGenerating(id) {
      await db.query(
        `UPDATE reportes
         SET pdf_status = 'generando',
             pdf_error = NULL,
             pdf_tokens_input = NULL,
             pdf_tokens_output = NULL,
             pdf_tokens_reasoning = NULL,
             pdf_tokens_total = NULL,
             pdf_tokens_cache_read = NULL,
             pdf_tokens_cache_write = NULL,
             pdf_cost_total = NULL
         WHERE id = $1`,
        [id]
      );
    },
    async markReady(fileName, metrics, id) {
      await db.query(
        `UPDATE reportes
         SET pdf_path = $1,
             pdf_status = 'listo',
             pdf_error = NULL,
             pdf_tokens_input = $2,
             pdf_tokens_output = $3,
             pdf_tokens_reasoning = $4,
             pdf_tokens_total = $5,
             pdf_tokens_cache_read = $6,
             pdf_tokens_cache_write = $7,
             pdf_cost_total = $8
         WHERE id = $9`,
        [
          fileName,
          metrics.pdf_tokens_input,
          metrics.pdf_tokens_output,
          metrics.pdf_tokens_reasoning,
          metrics.pdf_tokens_total,
          metrics.pdf_tokens_cache_read,
          metrics.pdf_tokens_cache_write,
          metrics.pdf_cost_total,
          id,
        ]
      );
    },
    async markError(message, metrics, id) {
      await db.query(
        `UPDATE reportes
         SET pdf_path = NULL,
             pdf_status = 'error',
             pdf_error = $1,
             pdf_tokens_input = $2,
             pdf_tokens_output = $3,
             pdf_tokens_reasoning = $4,
             pdf_tokens_total = $5,
             pdf_tokens_cache_read = $6,
             pdf_tokens_cache_write = $7,
             pdf_cost_total = $8
         WHERE id = $9`,
        [
          message,
          metrics.pdf_tokens_input,
          metrics.pdf_tokens_output,
          metrics.pdf_tokens_reasoning,
          metrics.pdf_tokens_total,
          metrics.pdf_tokens_cache_read,
          metrics.pdf_tokens_cache_write,
          metrics.pdf_cost_total,
          id,
        ]
      );
    },
    async getPromptContenido() {
      const row = await db.queryOne(
        "SELECT contenido FROM prompts WHERE clave = $1",
        ["reporte_ejecutivo"]
      );
      return row ? row.contenido : null;
    },
  };
}

function createPdfGenerator(options = {}) {
  const store = createPgStore(options.db || defaultDb);
  const dataDir = options.dataDir || path.join(__dirname, "..", "..", "data");
  const promptPath =
    options.promptPath ||
    path.join(__dirname, "..", "..", "prompts", "reporte_ejecutivo.txt");
  const rendererScriptPath =
    options.rendererScriptPath ||
    path.join(__dirname, "..", "..", "scripts", "render_reporte_ejecutivo.py");
  const plantillaScriptPath =
    options.plantillaScriptPath ||
    path.join(__dirname, "..", "..", "ejemplos", "plantilla_reporte_corporativo.py");
  const opencodeConfigPath =
    options.opencodeConfigPath || path.join(__dirname, "..", "..", "opencode.json");
  const env = buildOpencodeEnv(options.env || process.env);
  const timeoutMs = options.timeoutMs || Number(env.OPENCODE_TIMEOUT_MS) || 10 * 60 * 1000;
  const killGraceMs = options.killGraceMs || DEFAULT_KILL_GRACE_MS;
  const preferPromptFile = Boolean(options.preferPromptFile);
  const queuedIds = new Set();
  const queue = [];
  let running = false;
  let drainPromise = Promise.resolve();

  async function loadPrompt() {
    if (!preferPromptFile) {
      const fromDb = await store.getPromptContenido();
      if (fromDb != null) {
        return fromDb;
      }
    }
    if (fs.existsSync(promptPath)) {
      return fs.readFileSync(promptPath, "utf8");
    }
    return null;
  }

  async function processReport(id) {
    const tmpRoot = path.join(dataDir, "tmp");
    const pdfDir = path.join(dataDir, "pdfs");
    let workDir;
    let usageMetrics = createEmptyUsageMetrics();

    try {
      const row = await store.getReporte(id);
      if (!row) {
        throw new Error(`Reporte ${id} no existe`);
      }

      const prompt = await loadPrompt();
      if (!prompt) {
        throw new Error("El prompt para generar el PDF no existe o no esta configurado");
      }
      if (!isPromptReady(prompt)) {
        throw new Error("El prompt para generar el PDF no esta configurado");
      }

      if (!fs.existsSync(plantillaScriptPath)) {
        throw new Error("La plantilla de estilo corporativo no existe o no esta configurada");
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
      fs.writeFileSync(
        path.join(workDir, "reporte_metadata.json"),
        JSON.stringify(
          {
            equipo: row.equipo,
            ...buildReportDateContext(row.fecha_hora),
          },
          null,
          2
        )
      );
      fs.copyFileSync(plantillaScriptPath, path.join(workDir, "plantilla_reporte_corporativo.py"));

      if (fs.existsSync(opencodeConfigPath)) {
        fs.copyFileSync(opencodeConfigPath, path.join(workDir, "opencode.json"));
      }

      const result = await runOpencode({ id, workDir, prompt, env, timeoutMs, killGraceMs });
      usageMetrics = result.usageMetrics || usageMetrics;
      if (result.code !== 0) {
        if (result.timedOut) {
          const tail = truncateTail([result.stderr, result.stdout].filter(Boolean).join("\n"));
          throw new Error(
            tail
              ? `opencode excedio el tiempo limite (${timeoutMs}ms). Ultima salida del proceso:\n${tail}`
              : `opencode excedio el tiempo limite (${timeoutMs}ms) sin producir salida`
          );
        }
        const details = truncateTail([result.stderr, result.stdout].filter(Boolean).join("\n"));
        throw new Error(details || "opencode no genero reporte_normalizado.json");
      }

      const { normalizedPath } = readNormalizedReport(workDir);
      const draftPdfPath = path.join(workDir, "reporte_ejecutivo.pdf");
      const renderResult = await runRenderer({
        scriptPath: rendererScriptPath,
        inputPath: normalizedPath,
        outputPath: draftPdfPath,
        timeoutMs,
      });
      if (renderResult.code !== 0 || !fs.existsSync(draftPdfPath)) {
        const details = truncateTail(
          [renderResult.stderr, renderResult.stdout].filter(Boolean).join("\n")
        );
        throw new Error(details || "renderer no genero el PDF");
      }

      const fileName = `${id}.pdf`;
      fs.renameSync(draftPdfPath, path.join(pdfDir, fileName));
      const dbMetrics = usageMetricsToDbRow(usageMetrics);
      await store.markReady(fileName, dbMetrics, id);
    } catch (error) {
      const dbMetrics = usageMetricsToDbRow(usageMetrics);
      await store.markError(truncateTail(error.message), dbMetrics, id);
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

  async function encolarGeneracion(id) {
    const row = await store.getReporte(id);
    if (!row || row.pdf_status === "generando" || queuedIds.has(id)) {
      return false;
    }
    await store.markGenerating(id);
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

let defaultGenerator = null;

function getDefaultGenerator() {
  if (!defaultGenerator) {
    defaultGenerator = createPdfGenerator();
  }
  return defaultGenerator;
}

module.exports = {
  accumulateUsageFromEvent,
  createEmptyUsageMetrics,
  createPdfGenerator,
  createPgStore,
  buildOpencodeEnv,
  encolarGeneracion: (...args) => getDefaultGenerator().encolarGeneracion(...args),
  isPromptReady,
  truncateTail,
  usageMetricsToDbRow,
  findPdf,
};
