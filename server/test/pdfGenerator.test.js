const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

process.env.NODE_ENV = "test";

const { createMemoryStore } = require("./helpers/memoryStore");
const {
  createPdfGenerator,
  isPromptReady,
  truncateTail,
} = require("../src/services/pdfGenerator");

function makeDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "pdf-generator-test-"));
}

function makeDb(overrides) {
  return createMemoryStore(overrides);
}

function makeFakeOpencode(binDir, code) {
  const bin = path.join(binDir, "opencode");
  fs.writeFileSync(bin, code, { mode: 0o755 });
  return bin;
}

test("isPromptReady rejects empty and placeholder prompts", () => {
  assert.equal(isPromptReady(""), false);
  assert.equal(isPromptReady("REEMPLAZAR_PROMPT_EJECUTIVO"), false);
  assert.equal(isPromptReady("Genera el PDF con los tres reportes."), true);
});

test("truncateTail keeps the last characters", () => {
  assert.equal(truncateTail("abcdef", 3), "def");
  assert.equal(truncateTail("abc", 10), "abc");
});

test("generator creates report files, stores rendered pdf, and cleans work dir", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  const rendererScriptPath = path.join(root, "render.py");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");
  fs.writeFileSync(
    rendererScriptPath,
    [
      "import sys",
      "from pathlib import Path",
      "Path(sys.argv[2]).write_bytes(b'%PDF-1.4 fake pdf')",
    ].join("\n")
  );
  const plantillaScriptPath = path.join(root, "plantilla_reporte_corporativo.py");
  fs.writeFileSync(plantillaScriptPath, "# plantilla estilo\n");
  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
if (!fs.existsSync("plantilla_reporte_corporativo.py")) {
  console.error("missing plantilla_reporte_corporativo.py");
  process.exit(2);
}
fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
  metadata: {
    reportTitle: "Titulo",
    reportId: "ID",
    organization: "Org",
    equipo: "SERVER1",
    localDate: "2026-07-09",
    localDateTime: "2026-07-09 15:36:13",
    timeZone: "America/Monterrey"
  },
  sections: {
    hallazgos_y_recomendaciones: {
      title: "Hallazgos y recomendaciones",
      summary: "Resumen final",
      groups: {
        criticos: [{
          severity: "Critico",
          title: "Firewall off",
          evidence: "EnableFirewall = 0x0",
          recommendation: "Activar firewall"
        }],
        atencion: [],
        informativos: []
      }
    }
  }
}, null, 2));
process.exit(0);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    rendererScriptPath,
    plantillaScriptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  const queued = await generator.encolarGeneracion(1);
  assert.equal(queued, true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "listo");
  assert.equal(row.pdf_error, null);
  assert.equal(row.pdf_path, "1.pdf");
  assert.equal(fs.existsSync(path.join(dataDir, "pdfs", "1.pdf")), true);
  assert.equal(fs.readdirSync(path.join(dataDir, "tmp")).length, 0);
});

test("generator marks error when plantilla de estilo is missing", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  const missingPlantilla = path.join(root, "missing_plantilla.py");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    plantillaScriptPath: missingPlantilla,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /plantilla de estilo corporativo/i);
});

test("generator marks error when opencode does not produce reporte_normalizado.json", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");
  makeFakeOpencode(binDir, "#!/bin/sh\nprintf '%s' '%PDF-1.4 fake pdf' > output.pdf\nexit 0\n");

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /reporte_normalizado\.json/i);
});

test("generator stores generated pdf when normalized json is valid and renderer succeeds", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  const rendererScriptPath = path.join(root, "render.py");

  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");
  fs.writeFileSync(
    rendererScriptPath,
    [
      "import sys",
      "from pathlib import Path",
      "Path(sys.argv[2]).write_bytes(b'%PDF-1.4 fake pdf')",
    ].join("\n")
  );

  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
  metadata: {
    reportTitle: "Titulo",
    reportId: "ID",
    organization: "Org",
    equipo: "SERVER1",
    localDate: "2026-07-09",
    localDateTime: "2026-07-09 15:36:13",
    timeZone: "America/Monterrey"
  },
  sections: {
    hallazgos_y_recomendaciones: {
      title: "Hallazgos y recomendaciones",
      summary: "Resumen final",
      groups: {
        criticos: [{
          severity: "Critico",
          title: "Firewall off",
          evidence: "EnableFirewall = 0x0",
          recommendation: "Activar firewall"
        }],
        atencion: [],
        informativos: []
      }
    }
  }
}, null, 2));
process.exit(0);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    rendererScriptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "listo");
  assert.equal(row.pdf_error, null);
  assert.equal(row.pdf_path, "1.pdf");
  assert.equal(fs.existsSync(path.join(dataDir, "pdfs", "1.pdf")), true);
});

test("generator aggregates input output tokens and cost from opencode step_finish events", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  const rendererScriptPath = path.join(root, "render.py");

  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");
  fs.writeFileSync(
    rendererScriptPath,
    [
      "import sys",
      "from pathlib import Path",
      "Path(sys.argv[2]).write_bytes(b'%PDF-1.4 fake pdf')",
    ].join("\n")
  );

  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
const lines = [
  JSON.stringify({
    type: "step_finish",
    part: {
      tokens: {
        total: 1000,
        input: 200,
        output: 50,
        reasoning: 10,
        cache: { write: 2, read: 700 }
      },
      cost: 0.0123
    }
  }),
  JSON.stringify({
    type: "step_finish",
    part: {
      tokens: {
        total: 500,
        input: 100,
        output: 25,
        reasoning: 5,
        cache: { write: 1, read: 300 }
      },
      cost: 0.0045
    }
  })
];
for (const line of lines) process.stdout.write(line + "\\n");
fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
  metadata: {
    reportTitle: "Titulo",
    reportId: "ID",
    organization: "Org",
    equipo: "SERVER1",
    localDate: "2026-07-09",
    localDateTime: "2026-07-09 15:36:13",
    timeZone: "America/Monterrey"
  },
  sections: {
    hallazgos_y_recomendaciones: {
      title: "Hallazgos y recomendaciones",
      summary: "Resumen final",
      groups: {
        criticos: [{
          severity: "Critico",
          title: "Firewall off",
          evidence: "EnableFirewall = 0x0",
          recommendation: "Activar firewall"
        }],
        atencion: [],
        informativos: []
      }
    }
  }
}, null, 2));
process.exit(0);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    rendererScriptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.deepEqual(
    {
      pdf_tokens_input: row.pdf_tokens_input,
      pdf_tokens_output: row.pdf_tokens_output,
      pdf_tokens_reasoning: row.pdf_tokens_reasoning,
      pdf_tokens_total: row.pdf_tokens_total,
      pdf_tokens_cache_read: row.pdf_tokens_cache_read,
      pdf_tokens_cache_write: row.pdf_tokens_cache_write,
      pdf_cost_total: row.pdf_cost_total,
    },
    {
      pdf_tokens_input: 300,
      pdf_tokens_output: 75,
      pdf_tokens_reasoning: 15,
      pdf_tokens_total: 1500,
      pdf_tokens_cache_read: 1000,
      pdf_tokens_cache_write: 3,
      pdf_cost_total: 0.0168,
    }
  );
});

test("generator marks error when normalized json is invalid", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");

  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
  metadata: { reportTitle: "Titulo" },
  sections: {}
}, null, 2));
process.exit(0);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /metadata\.reportId|seccion final obligatoria/i);
});

test("generator marks error when renderer fails", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");

  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
  metadata: {
    reportTitle: "Titulo",
    reportId: "ID",
    organization: "Org",
    equipo: "SERVER1",
    localDate: "2026-07-09",
    localDateTime: "2026-07-09 15:36:13",
    timeZone: "America/Monterrey"
  },
  sections: {
    hallazgos_y_recomendaciones: {
      title: "Hallazgos y recomendaciones",
      summary: "Resumen final",
      groups: {
        criticos: [{
          severity: "Critico",
          title: "Firewall off",
          evidence: "EnableFirewall = 0x0",
          recommendation: "Activar firewall"
        }],
        atencion: [],
        informativos: []
      }
    }
  }
}, null, 2));
process.exit(0);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    rendererScriptPath: path.join(root, "missing-renderer.py"),
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /missing-renderer|no such file|can't open file/i);
});

test("generator prevents duplicate queueing while a report is generating", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  const rendererScriptPath = path.join(root, "render.py");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");
  fs.writeFileSync(
    rendererScriptPath,
    [
      "import sys",
      "from pathlib import Path",
      "Path(sys.argv[2]).write_bytes(b'%PDF-1.4 fake pdf')",
    ].join("\n")
  );
  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
setTimeout(() => {
  fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
    metadata: {
      reportTitle: "Titulo",
      reportId: "ID",
      organization: "Org",
      equipo: "SERVER1",
      localDate: "2026-07-09",
      localDateTime: "2026-07-09 15:36:13",
      timeZone: "America/Monterrey"
    },
    sections: {
      hallazgos_y_recomendaciones: {
        title: "Hallazgos y recomendaciones",
        summary: "Resumen final",
        groups: {
          criticos: [{
            severity: "Critico",
            title: "Firewall off",
            evidence: "EnableFirewall = 0x0",
            recommendation: "Activar firewall"
          }],
          atencion: [],
          informativos: []
        }
      }
    }
  }, null, 2));
  process.exit(0);
}, 1000);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    rendererScriptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  assert.equal(await generator.encolarGeneracion(1), false);
  await generator.drain();
});

test("generator marks error when prompt is still placeholder", async () => {
  const root = makeDir();
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "REEMPLAZAR_PROMPT_EJECUTIVO");

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: { ...process.env, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /prompt/i);
  assert.equal(row.pdf_path, null);
});

test("generator marks error when opencode fails without pdf", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(binDir, "#!/bin/sh\necho 'modelo invalido' >&2\nexit 2\n");

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "bad/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /modelo invalido/);
  assert.equal(row.pdf_path, null);
});

test("generator clears stale pdf_path when generation fails", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(binDir, "#!/bin/sh\necho 'fallo generacion' >&2\nexit 1\n");

  const db = makeDb();
  db.setPdfPath(1, "old.pdf");
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "bad/model" },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /fallo generacion/);
  assert.equal(row.pdf_path, null);
});

test("generator times out and cleans up when opencode ignores SIGTERM", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(
    binDir,
    "#!/usr/bin/env node\nprocess.on('SIGTERM', () => {});\nsetTimeout(() => {}, 5000);\n"
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 500,
    killGraceMs: 50,
  });

  const startedAt = Date.now();
  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const elapsedMs = Date.now() - startedAt;
  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /tiempo limite/i);
  assert.equal(row.pdf_path, null);
  assert.equal(fs.readdirSync(path.join(dataDir, "tmp")).length, 0);
  assert.ok(elapsedMs >= 500, `expected timeout to wait at least 500ms, got ${elapsedMs}ms`);
  assert.ok(elapsedMs < 1000, `expected timeout before 1000ms, got ${elapsedMs}ms`);
});

test("generator does not pass unrelated secrets to opencode", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  const rendererScriptPath = path.join(root, "render.py");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Extrae un reporte normalizado en JSON.");
  fs.writeFileSync(
    rendererScriptPath,
    [
      "import sys",
      "from pathlib import Path",
      "source = Path(sys.argv[1]).with_name('env.txt')",
      "Path(sys.argv[2]).write_text(source.read_text())",
    ].join("\n")
  );
  makeFakeOpencode(
    binDir,
    `#!/usr/bin/env node
const fs = require("node:fs");
const envText = Object.entries(process.env).map(([key, value]) => key + "=" + value).join("\\n");
fs.writeFileSync("env.txt", envText);
fs.writeFileSync("reporte_normalizado.json", JSON.stringify({
  metadata: {
    reportTitle: "Titulo",
    reportId: "ID",
    organization: "Org",
    equipo: "SERVER1",
    localDate: "2026-07-09",
    localDateTime: "2026-07-09 15:36:13",
    timeZone: "America/Monterrey"
  },
  sections: {
    hallazgos_y_recomendaciones: {
      title: "Hallazgos y recomendaciones",
      summary: "Resumen final",
      groups: {
        criticos: [{
          severity: "Critico",
          title: "Firewall off",
          evidence: "EnableFirewall = 0x0",
          recommendation: "Activar firewall"
        }],
        atencion: [],
        informativos: []
      }
    }
  }
}, null, 2));
process.exit(0);
`
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    rendererScriptPath,
    env: {
      PATH: `${binDir}${path.delimiter}${process.env.PATH}`,
      HOME: root,
      OPENCODE_MODEL: "test/model",
      OPENCODE_TRACE: "1",
      OPENAI_API_KEY: "openai-key",
      UNRELATED_SECRET: "must-not-leak",
    },
    timeoutMs: 5000,
  });

  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const envText = fs.readFileSync(path.join(dataDir, "pdfs", "1.pdf"), "utf8");
  assert.match(envText, /OPENCODE_TRACE=1/);
  assert.match(envText, /OPENAI_API_KEY=openai-key/);
  assert.equal(envText.includes("UNRELATED_SECRET"), false);
});

test("generator honors OPENCODE_TIMEOUT_MS from env when timeoutMs option is omitted", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(
    binDir,
    "#!/usr/bin/env node\nsetTimeout(() => {}, 2000);\n"
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    preferPromptFile: true,
    db,
    dataDir,
    promptPath,
    env: {
      PATH: `${binDir}${path.delimiter}${process.env.PATH}`,
      HOME: root,
      OPENCODE_MODEL: "test/model",
      OPENCODE_TIMEOUT_MS: "200",
    },
    killGraceMs: 100,
  });

  const startedAt = Date.now();
  assert.equal(await generator.encolarGeneracion(1), true);
  await generator.drain();

  const elapsedMs = Date.now() - startedAt;
  const row = db.getRow(1);
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /tiempo limite/i);
  assert.equal(row.pdf_path, null);
  assert.ok(elapsedMs < 1000, `expected env timeout (200ms) to kill the process well under 1s, got ${elapsedMs}ms`);
});
