const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const Database = require("better-sqlite3");

const moduleDbRoot = fs.mkdtempSync(path.join(os.tmpdir(), "pdf-generator-module-db-"));
process.env.DB_PATH = path.join(moduleDbRoot, "auditoria.db");

const { ensureReportesSchema } = require("../src/db");
const {
  createPdfGenerator,
  isPromptReady,
  truncateTail,
} = require("../src/services/pdfGenerator");

function makeDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "pdf-generator-test-"));
}

function makeDb() {
  const db = new Database(":memory:");
  ensureReportesSchema(db);
  db.prepare(
    "INSERT INTO reportes (equipo, reporte_sistema, reporte_red, reporte_logs) VALUES (?, ?, ?, ?)"
  ).run("SERVER1", "sistema", "red", "logs");
  return db;
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

test("generator creates report files, stores generated pdf, and cleans work dir", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(
    binDir,
    "#!/bin/sh\nprintf '%s' '%PDF-1.4 fake pdf' > output.pdf\nexit 0\n"
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  const queued = generator.encolarGeneracion(1);
  assert.equal(queued, true);
  await generator.drain();

  const row = db.prepare("SELECT pdf_status, pdf_error, pdf_path FROM reportes WHERE id = 1").get();
  assert.deepEqual(row, { pdf_status: "listo", pdf_error: null, pdf_path: "1.pdf" });
  assert.equal(fs.existsSync(path.join(dataDir, "pdfs", "1.pdf")), true);
  assert.equal(fs.readdirSync(path.join(dataDir, "tmp")).length, 0);
});

test("generator prevents duplicate queueing while a report is generating", async () => {
  const root = makeDir();
  const binDir = path.join(root, "bin");
  const dataDir = path.join(root, "data");
  const promptPath = path.join(root, "prompt.txt");
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(
    binDir,
    "#!/bin/sh\nsleep 1\nprintf '%s' '%PDF-1.4 fake pdf' > output.pdf\nexit 0\n"
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(generator.encolarGeneracion(1), true);
  assert.equal(generator.encolarGeneracion(1), false);
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
    db,
    dataDir,
    promptPath,
    env: { ...process.env, OPENCODE_MODEL: "test/model" },
    timeoutMs: 5000,
  });

  assert.equal(generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.prepare("SELECT pdf_status, pdf_error, pdf_path FROM reportes WHERE id = 1").get();
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
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "bad/model" },
    timeoutMs: 5000,
  });

  assert.equal(generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.prepare("SELECT pdf_status, pdf_error, pdf_path FROM reportes WHERE id = 1").get();
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
  db.prepare("UPDATE reportes SET pdf_path = ? WHERE id = 1").run("old.pdf");
  const generator = createPdfGenerator({
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "bad/model" },
    timeoutMs: 5000,
  });

  assert.equal(generator.encolarGeneracion(1), true);
  await generator.drain();

  const row = db.prepare("SELECT pdf_status, pdf_error, pdf_path FROM reportes WHERE id = 1").get();
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
    db,
    dataDir,
    promptPath,
    env: { ...process.env, PATH: `${binDir}${path.delimiter}${process.env.PATH}`, OPENCODE_MODEL: "test/model" },
    timeoutMs: 500,
    killGraceMs: 50,
  });

  const startedAt = Date.now();
  assert.equal(generator.encolarGeneracion(1), true);
  await generator.drain();

  const elapsedMs = Date.now() - startedAt;
  const row = db.prepare("SELECT pdf_status, pdf_error, pdf_path FROM reportes WHERE id = 1").get();
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
  fs.mkdirSync(binDir);
  fs.mkdirSync(dataDir);
  fs.writeFileSync(promptPath, "Genera un PDF ejecutivo usando los reportes.");
  makeFakeOpencode(
    binDir,
    "#!/bin/sh\nenv > output.pdf\nexit 0\n"
  );

  const db = makeDb();
  const generator = createPdfGenerator({
    db,
    dataDir,
    promptPath,
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

  assert.equal(generator.encolarGeneracion(1), true);
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
  assert.equal(generator.encolarGeneracion(1), true);
  await generator.drain();

  const elapsedMs = Date.now() - startedAt;
  const row = db.prepare("SELECT pdf_status, pdf_error, pdf_path FROM reportes WHERE id = 1").get();
  assert.equal(row.pdf_status, "error");
  assert.match(row.pdf_error, /tiempo limite/i);
  assert.equal(row.pdf_path, null);
  assert.ok(elapsedMs < 1000, `expected env timeout (200ms) to kill the process well under 1s, got ${elapsedMs}ms`);
});
