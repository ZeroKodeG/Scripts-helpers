#!/usr/bin/env node
/**
 * Migracion one-shot: SQLite (data/auditoria.db) -> Postgres (DATABASE_URL).
 * No migra usuarios/prompts (se reseed-ean). Los PDFs en data/pdfs/ se reutilizan.
 *
 * Lee SQLite con Python (stdlib sqlite3) — no requiere better-sqlite3 ni compilador.
 *
 * Uso (dentro del contenedor backend o en local con Python 3):
 *   DATABASE_URL=postgresql://... SQLITE_PATH=./data/auditoria.db npm run migrate:sqlite
 */
require("dotenv").config();
const path = require("path");
const fs = require("fs");
const { spawnSync } = require("child_process");
const { Pool } = require("pg");

const DUMP_PY = `
import json, sqlite3, sys

db_path = sys.argv[1]
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
conn.row_factory = sqlite3.Row
cur = conn.execute(
    """
    SELECT id, equipo, fecha_hora, reporte_sistema, reporte_red, reporte_logs,
           pdf_path, pdf_status, pdf_error,
           pdf_tokens_input, pdf_tokens_output, pdf_tokens_reasoning,
           pdf_tokens_total, pdf_tokens_cache_read, pdf_tokens_cache_write,
           pdf_cost_total
    FROM reportes
    ORDER BY id
    """
)
rows = []
for row in cur:
    item = {k: row[k] for k in row.keys()}
    rows.append(item)
conn.close()
json.dump(rows, sys.stdout, ensure_ascii=False)
`;

function readSqliteRows(sqlitePath) {
  const result = spawnSync("python3", ["-c", DUMP_PY, sqlitePath], {
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(
      `python3 no pudo leer SQLite (exit ${result.status}):\n${result.stderr || result.stdout}`
    );
  }
  return JSON.parse(result.stdout || "[]");
}

/** Postgres TEXT/UTF8 no admite NUL (0x00); SQLite si puede tenerlos en reportes. */
function scrubPgText(value) {
  if (value == null) return null;
  if (typeof value !== "string") return value;
  return value.replace(/\u0000/g, "");
}

async function main() {
  const sqlitePath =
    process.env.SQLITE_PATH || path.join(__dirname, "..", "data", "auditoria.db");
  if (!fs.existsSync(sqlitePath)) {
    console.error("No existe SQLite en", sqlitePath);
    process.exit(1);
  }
  if (!process.env.DATABASE_URL) {
    console.error("Falta DATABASE_URL");
    process.exit(1);
  }

  const rows = readSqliteRows(sqlitePath);
  console.log(`Migrando ${rows.length} reportes desde ${sqlitePath}...`);

  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const r of rows) {
      await client.query(
        `INSERT INTO reportes (
           id, equipo, fecha_hora, reporte_sistema, reporte_red, reporte_logs,
           pdf_path, pdf_status, pdf_error,
           pdf_tokens_input, pdf_tokens_output, pdf_tokens_reasoning,
           pdf_tokens_total, pdf_tokens_cache_read, pdf_tokens_cache_write,
           pdf_cost_total
         ) VALUES (
           $1,$2,$3,$4,$5,$6,$7,COALESCE($8,'pendiente'),$9,
           $10,$11,$12,$13,$14,$15,$16
         )
         ON CONFLICT (id) DO NOTHING`,
        [
          r.id,
          scrubPgText(r.equipo),
          r.fecha_hora,
          scrubPgText(r.reporte_sistema),
          scrubPgText(r.reporte_red),
          scrubPgText(r.reporte_logs),
          scrubPgText(r.pdf_path),
          scrubPgText(r.pdf_status),
          scrubPgText(r.pdf_error),
          r.pdf_tokens_input,
          r.pdf_tokens_output,
          r.pdf_tokens_reasoning,
          r.pdf_tokens_total,
          r.pdf_tokens_cache_read,
          r.pdf_tokens_cache_write,
          r.pdf_cost_total,
        ]
      );
    }
    await client.query(
      "SELECT setval(pg_get_serial_sequence('reportes','id'), COALESCE((SELECT MAX(id) FROM reportes), 1))"
    );
    await client.query("COMMIT");
    console.log("Migracion completada.");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
