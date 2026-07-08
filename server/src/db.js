const path = require("path");
const fs = require("fs");
const Database = require("better-sqlite3");

const dbPath = process.env.DB_PATH || "./data/auditoria.db";
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

const db = new Database(dbPath);
db.pragma("journal_mode = WAL");

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

module.exports = db;
