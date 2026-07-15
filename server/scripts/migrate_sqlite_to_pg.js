#!/usr/bin/env node
/**
 * Migracion one-shot: SQLite (data/auditoria.db) -> Postgres (DATABASE_URL).
 * No migra usuarios/prompts (se reseed-ean). Los PDFs en data/pdfs/ se reutilizan.
 *
 * Uso:
 *   DATABASE_URL=postgresql://... SQLITE_PATH=./data/auditoria.db node scripts/migrate_sqlite_to_pg.js
 *
 * Requiere el paquete better-sqlite3 instalado temporalmente, o pasar SQLITE_PATH
 * y tener `sqlite3` CLI. Preferido: npm i better-sqlite3 --no-save && node ...
 */
require("dotenv").config();
const path = require("path");
const fs = require("fs");
const { Pool } = require("pg");

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

  let Database;
  try {
    Database = require("better-sqlite3");
  } catch {
    console.error(
      "Instala better-sqlite3 temporalmente: npm i better-sqlite3 --no-save"
    );
    process.exit(1);
  }

  const sqlite = new Database(sqlitePath, { readonly: true });
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });

  const rows = sqlite
    .prepare(
      `SELECT id, equipo, fecha_hora, reporte_sistema, reporte_red, reporte_logs,
              pdf_path, pdf_status, pdf_error,
              pdf_tokens_input, pdf_tokens_output, pdf_tokens_reasoning,
              pdf_tokens_total, pdf_tokens_cache_read, pdf_tokens_cache_write,
              pdf_cost_total
       FROM reportes ORDER BY id`
    )
    .all();

  console.log(`Migrando ${rows.length} reportes...`);

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
          r.equipo,
          r.fecha_hora,
          r.reporte_sistema,
          r.reporte_red,
          r.reporte_logs,
          r.pdf_path,
          r.pdf_status,
          r.pdf_error,
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
    sqlite.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
