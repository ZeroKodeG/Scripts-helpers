# Generacion PDF Opencode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an asynchronous `Generar PDF` workflow that runs opencode on the VPS, generates an executive PDF from the three stored reports, and attaches it automatically to the dashboard row.

**Architecture:** SQLite stores durable PDF generation state. An in-memory Node queue with concurrency 1 launches `opencode run --auto` in a per-report temporary directory, moves the resulting PDF into `server/data/pdfs/`, and updates the row. The EJS dashboard renders state from SQLite and auto-refreshes only while generation is active.

**Tech Stack:** Node.js, Express, EJS, better-sqlite3, multer, Docker Compose, opencode CLI, Node built-in test runner.

---

## File Structure

- Modify `server/package.json`: add a `test` script using Node's built-in test runner.
- Modify `server/src/db.js`: keep DB initialization, add idempotent column migrations, export small migration helpers for tests.
- Modify `server/src/index.js`: mark interrupted `generando` rows as `error` before the server starts.
- Create `server/src/services/pdfGenerator.js`: own all queueing, temp directory setup, opencode spawning, PDF discovery, cleanup, and status updates.
- Modify `server/src/routes/web.js`: import the generator, select new PDF status fields, add `POST /reportes/:id/generar-pdf`, and update manual uploads to set `pdf_status='listo'`.
- Modify `server/src/views/dashboard.ejs`: render the four PDF states and add conditional auto-refresh.
- Modify `server/public/css/style.css`: add error badge and compact inline PDF action styles.
- Create `server/prompts/reporte_ejecutivo.txt`: checked-in placeholder prompt with marker `REEMPLAZAR_PROMPT_EJECUTIVO`.
- Modify `server/Dockerfile`: install opencode CLI and copy `prompts/` into the image.
- Modify `server/.env.example`: document opencode variables.
- Modify `docker-compose.yml`: read secrets from `server/.env` using `env_file` while keeping fixed container `PORT` and `DB_PATH`.
- Modify `server/README.md`: document opencode setup, security caveat, and PDF generation behavior.
- Create `server/test/db.test.js`: verify idempotent migrations.
- Create `server/test/pdfGenerator.test.js`: verify prompt validation, duplicate queue guard, success path with a fake opencode binary, error path, and cleanup.

## Task 1: Add Node Test Harness

**Files:**
- Modify: `server/package.json`

- [ ] **Step 1: Add the test script**

Update `server/package.json` scripts to:

```json
"scripts": {
  "start": "node src/index.js",
  "dev": "node --watch src/index.js",
  "test": "node --test"
}
```

- [ ] **Step 2: Verify the empty test runner works**

Run: `npm test --prefix server`

Expected: command exits 0 with Node test runner output showing no failing tests.

- [ ] **Step 3: Commit**

```bash
git add server/package.json
git commit -m "test: add node test runner"
```

## Task 2: Add Idempotent PDF Status Migration

**Files:**
- Modify: `server/src/db.js`
- Create: `server/test/db.test.js`

- [ ] **Step 1: Write the failing migration tests**

Create `server/test/db.test.js`:

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const Database = require("better-sqlite3");

const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), "db-test-"));
process.env.DB_PATH = path.join(testRoot, "auditoria.db");

const { ensureReportesSchema } = require("../src/db");

function columns(db) {
  return db.prepare("PRAGMA table_info(reportes)").all().map((column) => column.name);
}

test("ensureReportesSchema creates pdf status columns", () => {
  const db = new Database(":memory:");

  ensureReportesSchema(db);

  const names = columns(db);
  assert.ok(names.includes("pdf_status"));
  assert.ok(names.includes("pdf_error"));

  const row = db.prepare("SELECT pdf_status, pdf_error FROM reportes").get();
  assert.equal(row, undefined);
});

test("ensureReportesSchema can run more than once", () => {
  const db = new Database(":memory:");

  ensureReportesSchema(db);
  ensureReportesSchema(db);

  const names = columns(db);
  assert.equal(names.filter((name) => name === "pdf_status").length, 1);
  assert.equal(names.filter((name) => name === "pdf_error").length, 1);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm test --prefix server -- server/test/db.test.js`

Expected: FAIL with `ensureReportesSchema` not exported or not a function.

- [ ] **Step 3: Implement schema helper and migrations**

Replace `server/src/db.js` with:

```js
const path = require("path");
const fs = require("fs");
const Database = require("better-sqlite3");

const dbPath = process.env.DB_PATH || "./data/auditoria.db";
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

function hasColumn(db, table, column) {
  return db.prepare(`PRAGMA table_info(${table})`).all().some((info) => info.name === column);
}

function ensureReportesSchema(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS reportes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      equipo TEXT NOT NULL,
      fecha_hora TEXT NOT NULL DEFAULT (datetime('now')),
      reporte_sistema TEXT,
      reporte_red TEXT,
      reporte_logs TEXT,
      pdf_path TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_reportes_equipo ON reportes(equipo);
    CREATE INDEX IF NOT EXISTS idx_reportes_fecha ON reportes(fecha_hora DESC);
  `);

  if (!hasColumn(db, "reportes", "pdf_status")) {
    db.exec("ALTER TABLE reportes ADD COLUMN pdf_status TEXT NOT NULL DEFAULT 'pendiente'");
  }

  if (!hasColumn(db, "reportes", "pdf_error")) {
    db.exec("ALTER TABLE reportes ADD COLUMN pdf_error TEXT");
  }
}

const db = new Database(dbPath);
db.pragma("journal_mode = WAL");
ensureReportesSchema(db);

module.exports = db;
module.exports.ensureReportesSchema = ensureReportesSchema;
module.exports.hasColumn = hasColumn;
```

- [ ] **Step 4: Run the migration tests**

Run: `npm test --prefix server -- server/test/db.test.js`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/db.js server/test/db.test.js
git commit -m "feat: add pdf generation status columns"
```

## Task 3: Mark Interrupted Generations On Startup

**Files:**
- Modify: `server/src/index.js`

- [ ] **Step 1: Add startup recovery update**

In `server/src/index.js`, import the DB and run the recovery after the `API_KEY` check and before creating the Express app:

```js
const db = require("./db");

db.prepare(
  "UPDATE reportes SET pdf_status = 'error', pdf_error = 'Interrumpido por reinicio del backend' WHERE pdf_status = 'generando'"
).run();
```

Keep the existing route imports. The top of the file should have:

```js
require("dotenv").config();
const path = require("path");
const express = require("express");
const session = require("express-session");

const db = require("./db");
const apiRoutes = require("./routes/api");
const webRoutes = require("./routes/web");
```

- [ ] **Step 2: Run syntax and tests**

Run: `node --check server/src/index.js`

Expected: no output and exit 0.

Run: `npm test --prefix server`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add server/src/index.js
git commit -m "feat: recover interrupted pdf generations"
```

## Task 4: Build PDF Generator Service

**Files:**
- Create: `server/src/services/pdfGenerator.js`
- Create: `server/test/pdfGenerator.test.js`

- [ ] **Step 1: Write failing tests for helpers and generation paths**

Create `server/test/pdfGenerator.test.js`:

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test --prefix server -- server/test/pdfGenerator.test.js`

Expected: FAIL with missing module `../src/services/pdfGenerator`.

- [ ] **Step 3: Implement `pdfGenerator.js`**

Create `server/src/services/pdfGenerator.js`:

```js
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");

const db = require("../db");

const DEFAULT_DATA_DIR = path.join(__dirname, "..", "..", "data");
const DEFAULT_PROMPT_PATH = path.join(__dirname, "..", "..", "prompts", "reporte_ejecutivo.txt");
const PLACEHOLDER_MARKER = "REEMPLAZAR_PROMPT_EJECUTIVO";
const DEFAULT_TIMEOUT_MS = 10 * 60 * 1000;
const ERROR_LIMIT = 2000;

function truncateTail(value, limit = ERROR_LIMIT) {
  const text = String(value || "").trim();
  if (text.length <= limit) return text;
  return text.slice(text.length - limit);
}

function isPromptReady(prompt) {
  const text = String(prompt || "").trim();
  return text.length > 0 && !text.includes(PLACEHOLDER_MARKER);
}

function findPdf(workDir) {
  const entries = fs.readdirSync(workDir, { withFileTypes: true });
  const pdf = entries.find((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".pdf"));
  return pdf ? path.join(workDir, pdf.name) : null;
}

function runOpencode({ prompt, workDir, env, timeoutMs }) {
  return new Promise((resolve) => {
    const child = spawn(
      "opencode",
      ["run", "--auto", "--model", env.OPENCODE_MODEL, "--dir", workDir, "--format", "json", prompt],
      { cwd: workDir, env }
    );

    let stderr = "";
    let stdout = "";
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ code: 1, stderr: error.message, stdout, timedOut });
    });

    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, stderr, stdout, timedOut });
    });
  });
}

function createPdfGenerator(options = {}) {
  const database = options.db || db;
  const dataDir = options.dataDir || DEFAULT_DATA_DIR;
  const promptPath = options.promptPath || DEFAULT_PROMPT_PATH;
  const env = options.env || process.env;
  const timeoutMs = Number(options.timeoutMs || env.OPENCODE_TIMEOUT_MS || DEFAULT_TIMEOUT_MS);
  const tmpDir = path.join(dataDir, "tmp");
  const pdfDir = path.join(dataDir, "pdfs");
  const queue = [];
  const queuedIds = new Set();
  let processing = false;
  let drainResolver = null;

  fs.mkdirSync(tmpDir, { recursive: true });
  fs.mkdirSync(pdfDir, { recursive: true });

  function finishDrainIfIdle() {
    if (!processing && queue.length === 0 && drainResolver) {
      const resolve = drainResolver;
      drainResolver = null;
      resolve();
    }
  }

  function markError(id, message) {
    database
      .prepare("UPDATE reportes SET pdf_status = 'error', pdf_error = ? WHERE id = ?")
      .run(truncateTail(message || "Error generando PDF"), id);
  }

  async function processOne(id) {
    const workDir = path.join(tmpDir, `${id}-${crypto.randomBytes(8).toString("hex")}`);
    fs.mkdirSync(workDir, { recursive: true });

    try {
      if (!env.OPENCODE_MODEL) {
        markError(id, "Falta configurar OPENCODE_MODEL en el entorno");
        return;
      }

      const row = database
        .prepare("SELECT reporte_sistema, reporte_red, reporte_logs FROM reportes WHERE id = ?")
        .get(id);

      if (!row) {
        markError(id, "Reporte no encontrado");
        return;
      }

      const prompt = fs.existsSync(promptPath) ? fs.readFileSync(promptPath, "utf8") : "";
      if (!isPromptReady(prompt)) {
        markError(id, "El prompt de PDF no esta listo. Reemplaza REEMPLAZAR_PROMPT_EJECUTIVO en server/prompts/reporte_ejecutivo.txt");
        return;
      }

      fs.writeFileSync(path.join(workDir, "reporte_sistema.txt"), row.reporte_sistema || "");
      fs.writeFileSync(path.join(workDir, "reporte_red.txt"), row.reporte_red || "");
      fs.writeFileSync(path.join(workDir, "reporte_logs.txt"), row.reporte_logs || "");

      const result = await runOpencode({ prompt, workDir, env, timeoutMs });
      const pdfPath = findPdf(workDir);

      if (result.code === 0 && pdfPath) {
        const fileName = `${id}.pdf`;
        fs.renameSync(pdfPath, path.join(pdfDir, fileName));
        database
          .prepare("UPDATE reportes SET pdf_path = ?, pdf_status = 'listo', pdf_error = NULL WHERE id = ?")
          .run(fileName, id);
        return;
      }

      const error = result.timedOut
        ? `Timeout generando PDF despues de ${timeoutMs} ms`
        : result.stderr || result.stdout || `opencode termino con codigo ${result.code} sin generar PDF`;
      markError(id, error);
    } finally {
      fs.rmSync(workDir, { recursive: true, force: true });
    }
  }

  async function processNext() {
    if (processing) return;
    processing = true;

    while (queue.length > 0) {
      const id = queue.shift();
      queuedIds.delete(id);
      await processOne(id);
    }

    processing = false;
    finishDrainIfIdle();
  }

  function encolarGeneracion(id) {
    const reportId = Number(id);
    if (!Number.isInteger(reportId) || reportId <= 0) return false;
    if (queuedIds.has(reportId)) return false;

    const row = database.prepare("SELECT pdf_status FROM reportes WHERE id = ?").get(reportId);
    if (!row || row.pdf_status === "generando") return false;

    database
      .prepare("UPDATE reportes SET pdf_status = 'generando', pdf_error = NULL WHERE id = ?")
      .run(reportId);
    queuedIds.add(reportId);
    queue.push(reportId);
    processNext();
    return true;
  }

  function drain() {
    if (!processing && queue.length === 0) return Promise.resolve();
    return new Promise((resolve) => {
      drainResolver = resolve;
    });
  }

  return { encolarGeneracion, drain };
}

const defaultGenerator = createPdfGenerator();

module.exports = {
  encolarGeneracion: defaultGenerator.encolarGeneracion,
  createPdfGenerator,
  isPromptReady,
  truncateTail,
};
```

- [ ] **Step 4: Run service tests**

Run: `npm test --prefix server -- server/test/pdfGenerator.test.js`

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run: `npm test --prefix server`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/src/services/pdfGenerator.js server/test/pdfGenerator.test.js
git commit -m "feat: add opencode pdf generation service"
```

## Task 5: Add Placeholder Prompt

**Files:**
- Create: `server/prompts/reporte_ejecutivo.txt`

- [ ] **Step 1: Create the prompt placeholder**

Create `server/prompts/reporte_ejecutivo.txt`:

```text
REEMPLAZAR_PROMPT_EJECUTIVO

Este archivo debe contener el prompt final para opencode.

El backend escribira estos tres archivos en el directorio de trabajo antes de llamar a opencode:

- reporte_sistema.txt
- reporte_red.txt
- reporte_logs.txt

El prompt final debe indicar que se genere un PDF ejecutivo y que el PDF quede guardado dentro del directorio de trabajo.
```

- [ ] **Step 2: Run tests**

Run: `npm test --prefix server`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add server/prompts/reporte_ejecutivo.txt
git commit -m "docs: add executive pdf prompt placeholder"
```

## Task 6: Wire Web Routes To Queue

**Files:**
- Modify: `server/src/routes/web.js`

- [ ] **Step 1: Import the generator**

Add near the existing imports:

```js
const { encolarGeneracion } = require("../services/pdfGenerator");
```

- [ ] **Step 2: Select status fields in dashboard query**

Change both dashboard `SELECT` statements from selecting only `id, equipo, fecha_hora, pdf_path` to:

```sql
SELECT id, equipo, fecha_hora, pdf_path, pdf_status, pdf_error FROM reportes
```

The filtered query remains:

```js
"SELECT id, equipo, fecha_hora, pdf_path, pdf_status, pdf_error FROM reportes WHERE equipo = ? ORDER BY fecha_hora DESC"
```

The unfiltered query remains:

```js
"SELECT id, equipo, fecha_hora, pdf_path, pdf_status, pdf_error FROM reportes ORDER BY fecha_hora DESC"
```

- [ ] **Step 3: Add generate route**

Add before the manual PDF upload route:

```js
router.post(
  "/reportes/:id/generar-pdf",
  express.urlencoded({ extended: false }),
  requireSession,
  requireCsrf,
  (req, res) => {
    encolarGeneracion(req.params.id);
    res.redirect("/dashboard");
  }
);
```

- [ ] **Step 4: Update manual upload status**

Replace the existing manual upload update with:

```js
db.prepare("UPDATE reportes SET pdf_path = ?, pdf_status = 'listo', pdf_error = NULL WHERE id = ?").run(
  `${req.params.id}.pdf`,
  req.params.id
);
```

- [ ] **Step 5: Verify syntax and tests**

Run: `node --check server/src/routes/web.js`

Expected: no output and exit 0.

Run: `npm test --prefix server`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/src/routes/web.js
git commit -m "feat: add pdf generation web route"
```

## Task 7: Update Dashboard UI

**Files:**
- Modify: `server/src/views/dashboard.ejs`
- Modify: `server/public/css/style.css`

- [ ] **Step 1: Add conditional auto-refresh**

In `server/src/views/dashboard.ejs`, add this inside `<head>` after the stylesheet link:

```ejs
  <% if (reportes.some(function(r) { return r.pdf_status === "generando"; })) { %>
    <meta http-equiv="refresh" content="8">
  <% } %>
```

- [ ] **Step 2: Replace the PDF cell markup**

Replace the current `<td>` PDF block with:

```ejs
              <td>
                <% if (r.pdf_status === "listo" && r.pdf_path) { %>
                  <div class="pdf-actions">
                    <a class="badge badge-ok" href="/reportes/<%= r.id %>/pdf">PDF &#10003; Descargar</a>
                    <form class="inline-form" method="post" action="/reportes/<%= r.id %>/generar-pdf">
                      <input type="hidden" name="_csrf" value="<%= csrfToken %>">
                      <button class="link-button" type="submit">Regenerar</button>
                    </form>
                  </div>
                <% } else if (r.pdf_status === "generando") { %>
                  <span class="badge badge-pending">Generando...</span>
                <% } else if (r.pdf_status === "error") { %>
                  <div class="pdf-pending">
                    <span class="badge badge-error" title="<%= r.pdf_error || 'Error generando PDF' %>">Error: <%= (r.pdf_error || 'Error generando PDF').slice(0, 80) %></span>
                    <form class="inline-form" method="post" action="/reportes/<%= r.id %>/generar-pdf">
                      <input type="hidden" name="_csrf" value="<%= csrfToken %>">
                      <button type="submit">Reintentar</button>
                    </form>
                  </div>
                <% } else { %>
                  <div class="pdf-pending">
                    <form class="inline-form" method="post" action="/reportes/<%= r.id %>/generar-pdf">
                      <input type="hidden" name="_csrf" value="<%= csrfToken %>">
                      <button type="submit">Generar PDF</button>
                    </form>
                    <form class="pdf-form" method="post" action="/reportes/<%= r.id %>/pdf" enctype="multipart/form-data">
                      <input type="hidden" name="_csrf" value="<%= csrfToken %>">
                      <input type="file" name="pdf" accept="application/pdf" required>
                      <button type="submit">Subir</button>
                    </form>
                  </div>
                <% } %>
              </td>
```

- [ ] **Step 3: Add CSS classes**

Append these styles after `.badge-pending` in `server/public/css/style.css`:

```css
.badge-error {
  background: var(--danger-soft);
  color: var(--danger);
}

.pdf-actions {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.35rem;
}

.inline-form {
  display: inline-flex;
  align-items: center;
  margin: 0;
}

.inline-form button,
.link-button {
  padding: 0.3rem 0.65rem;
  font-size: 0.78rem;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--surface);
  color: var(--text);
  cursor: pointer;
}

.inline-form button:hover,
.link-button:hover {
  background: var(--accent-soft);
  border-color: var(--accent-soft);
  color: var(--accent);
}

.link-button {
  border: none;
  padding-left: 0;
  padding-right: 0;
  color: var(--accent);
  background: transparent;
}
```

- [ ] **Step 4: Verify syntax and tests**

Run: `node --check server/src/routes/web.js`

Expected: no output and exit 0.

Run: `npm test --prefix server`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/src/views/dashboard.ejs server/public/css/style.css
git commit -m "feat: show pdf generation states in dashboard"
```

## Task 8: Update Docker And Environment Config

**Files:**
- Modify: `server/Dockerfile`
- Modify: `server/.env.example`
- Modify: `docker-compose.yml`

- [ ] **Step 1: Install opencode and copy prompts in Dockerfile**

Modify `server/Dockerfile` runtime stage:

```dockerfile
# ---- runtime: imagen final, sin herramientas de compilacion ----
FROM node:20-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production

RUN npm install -g opencode-ai

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY public ./public
COPY prompts ./prompts
```

Keep the existing `EXPOSE`, `HEALTHCHECK`, and `CMD` lines.

- [ ] **Step 2: Add opencode env examples**

Append to `server/.env.example`:

```dotenv
OPENCODE_MODEL=provider/modelo
OPENCODE_TIMEOUT_MS=600000

# Configura la API key segun el proveedor elegido por OPENCODE_MODEL.
# OPENAI_API_KEY=sk-...
# ZHIPU_API_KEY=...
```

- [ ] **Step 3: Use env_file in docker compose**

Modify `docker-compose.yml` backend service to:

```yaml
services:
  backend:
    build:
      context: ./server
    container_name: auditoria-backend
    restart: unless-stopped
    env_file:
      - ./server/.env
    environment:
      - PORT=3000
      - DB_PATH=./data/auditoria.db
    volumes:
      - ./server/data:/app/data
```

- [ ] **Step 4: Verify Dockerfile syntax and package availability**

Run: `npm view opencode-ai version`

Expected: prints a version and exits 0.

Run: `docker compose config`

Expected: config renders without errors. If `server/.env` is missing locally, create it from `server/.env.example` before running this command and set dummy non-secret values.

- [ ] **Step 5: Commit**

```bash
git add server/Dockerfile server/.env.example docker-compose.yml
git commit -m "chore: configure opencode runtime environment"
```

## Task 9: Document Setup, Risk, And Operation

**Files:**
- Modify: `server/README.md`

- [ ] **Step 1: Update setup instructions**

In `server/README.md`, update both Docker and local setup sections so `.env` editing mentions `API_KEY`, `SESSION_SECRET`, `OPENCODE_MODEL`, `OPENCODE_TIMEOUT_MS`, and the provider API key.

- [ ] **Step 2: Add PDF generation section**

Add this section after `## Datos`:

```md
## Generacion automatica de PDF

El dashboard permite generar un PDF ejecutivo desde cada fila con el boton `Generar PDF`. El backend encola la generacion, escribe los tres reportes en un directorio temporal y ejecuta `opencode run --auto` con el prompt versionado en `prompts/reporte_ejecutivo.txt`.

Variables requeridas en `.env`:

- `OPENCODE_MODEL`: modelo fijo para todas las generaciones, por ejemplo `openai/gpt-4.1` o el proveedor/modelo configurado para opencode.
- `OPENCODE_TIMEOUT_MS`: timeout del proceso, por defecto `600000`.
- API key del proveedor elegido por `OPENCODE_MODEL`, por ejemplo `OPENAI_API_KEY` o `ZHIPU_API_KEY`.

Antes de usarlo en produccion, reemplazar el marcador `REEMPLAZAR_PROMPT_EJECUTIVO` en `prompts/reporte_ejecutivo.txt` por el prompt final. Mientras el marcador siga presente, la generacion falla a proposito con un error visible en el dashboard.

El estado se guarda en SQLite:

- `pendiente`: todavia no se genero PDF.
- `generando`: opencode esta corriendo o el reporte esta en cola.
- `listo`: existe `data/pdfs/<id>.pdf` y el dashboard muestra el link de descarga.
- `error`: la generacion fallo y se puede reintentar desde el dashboard.
```

- [ ] **Step 3: Add security caveat**

Add this section after the PDF generation section:

```md
## Nota de seguridad sobre opencode

La generacion automatica usa `opencode run --auto`. Eso permite que opencode apruebe permisos y ejecute codigo generado por el LLM dentro del VPS. Este proyecto no agrega sandboxing fuerte. Las mitigaciones son un directorio temporal por reporte, timeout del proceso y cola con concurrencia 1. Usar esta funcion solo con prompts propios y reportes de origen confiable.
```

- [ ] **Step 4: Verify docs mention all required variables**

Run: `grep -n "OPENCODE_MODEL\|OPENCODE_TIMEOUT_MS\|OPENAI_API_KEY\|ZHIPU_API_KEY\|REEMPLAZAR_PROMPT_EJECUTIVO" server/README.md server/.env.example`

Expected: each required name appears at least once.

- [ ] **Step 5: Commit**

```bash
git add server/README.md
git commit -m "docs: document opencode pdf generation"
```

## Task 10: Manual End-To-End Verification

**Files:**
- No code changes expected.

- [ ] **Step 1: Run automated tests**

Run: `npm test --prefix server`

Expected: PASS.

- [ ] **Step 2: Build Docker image**

Run: `docker compose build`

Expected: image builds successfully and installs opencode.

- [ ] **Step 3: Verify opencode binary inside image**

Run: `docker compose run --rm backend opencode --version`

Expected: prints opencode version and exits 0.

- [ ] **Step 4: Verify placeholder failure path locally**

Run the backend with the placeholder prompt still present:

```bash
npm start --prefix server
```

In another terminal, create a report:

```bash
curl -X POST http://localhost:3000/api/reportes \
  -H "X-API-Key: TU_API_KEY" \
  -F "equipo=PRUEBA" \
  -F "reporte_sistema=contenido sistema" \
  -F "reporte_red=contenido red" \
  -F "reporte_logs=contenido logs"
```

Open `/dashboard`, click `Generar PDF`, wait for refresh, and confirm the row becomes `error` with a prompt-related message.

- [ ] **Step 5: Verify success path with a real prompt and credentials**

Replace `server/prompts/reporte_ejecutivo.txt` with the final prompt, configure a real `OPENCODE_MODEL` and provider API key in `server/.env`, restart the backend, click `Reintentar`, and confirm:

- Dashboard shows `Generando...` first.
- Dashboard refreshes automatically.
- Dashboard eventually shows `PDF ✓ Descargar`.
- `server/data/pdfs/<id>.pdf` exists and opens as a valid PDF.

- [ ] **Step 6: Verify interrupted generation recovery**

While a row is `generando`, stop the backend process, start it again, reload `/dashboard`, and confirm the row is `error` with message `Interrumpido por reinicio del backend`.

- [ ] **Step 7: Final commit if manual verification required changes**

If any fixes were needed during verification:

```bash
git add <changed-files>
git commit -m "fix: complete pdf generation verification"
```

## Self-Review

- Spec coverage: DB migration, startup recovery, placeholder prompt, generator queue, web route, dashboard states, auto-refresh, Docker/env, security docs, and verification are each covered by a task.
- Placeholder scan: The plan intentionally references the prompt marker `REEMPLAZAR_PROMPT_EJECUTIVO`; there are no unresolved implementation placeholders.
- Type consistency: The plan consistently uses `pdf_status`, `pdf_error`, `encolarGeneracion`, `createPdfGenerator`, `isPromptReady`, and `truncateTail`.
