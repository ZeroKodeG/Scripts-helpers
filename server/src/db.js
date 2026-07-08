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
