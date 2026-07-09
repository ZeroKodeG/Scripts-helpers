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
  assert.ok(names.includes("pdf_tokens_input"));
  assert.ok(names.includes("pdf_tokens_output"));
  assert.ok(names.includes("pdf_cost_total"));

  const row = db
    .prepare("SELECT pdf_status, pdf_error, pdf_tokens_input, pdf_tokens_output, pdf_cost_total FROM reportes")
    .get();
  assert.equal(row, undefined);
});

test("ensureReportesSchema can run more than once", () => {
  const db = new Database(":memory:");

  ensureReportesSchema(db);
  ensureReportesSchema(db);

  const names = columns(db);
  assert.equal(names.filter((name) => name === "pdf_status").length, 1);
  assert.equal(names.filter((name) => name === "pdf_error").length, 1);
  assert.equal(names.filter((name) => name === "pdf_tokens_input").length, 1);
  assert.equal(names.filter((name) => name === "pdf_tokens_output").length, 1);
  assert.equal(names.filter((name) => name === "pdf_cost_total").length, 1);
});
