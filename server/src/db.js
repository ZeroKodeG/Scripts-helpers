const fs = require("fs");
const path = require("path");
const { Pool } = require("pg");

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL && process.env.NODE_ENV !== "test") {
  console.warn(
    "DATABASE_URL no esta definido. El backend necesita Postgres (ver .env.example)."
  );
}

const pool = new Pool(
  DATABASE_URL
    ? { connectionString: DATABASE_URL }
    : {
        host: process.env.PGHOST || "localhost",
        port: Number(process.env.PGPORT || 5432),
        user: process.env.PGUSER || "auditoria",
        password: process.env.PGPASSWORD || "auditoria",
        database: process.env.PGDATABASE || "auditoria",
      }
);

async function query(text, params = []) {
  return pool.query(text, params);
}

async function queryOne(text, params = []) {
  const result = await pool.query(text, params);
  return result.rows[0] || null;
}

async function queryAll(text, params = []) {
  const result = await pool.query(text, params);
  return result.rows;
}

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS reportes (
      id SERIAL PRIMARY KEY,
      equipo TEXT NOT NULL,
      fecha_hora TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      reporte_sistema TEXT,
      reporte_red TEXT,
      reporte_logs TEXT,
      pdf_path TEXT,
      pdf_status TEXT NOT NULL DEFAULT 'pendiente',
      pdf_error TEXT,
      pdf_tokens_input INTEGER,
      pdf_tokens_output INTEGER,
      pdf_tokens_reasoning INTEGER,
      pdf_tokens_total INTEGER,
      pdf_tokens_cache_read INTEGER,
      pdf_tokens_cache_write INTEGER,
      pdf_cost_total DOUBLE PRECISION
    );

    CREATE INDEX IF NOT EXISTS idx_reportes_equipo ON reportes(equipo);
    CREATE INDEX IF NOT EXISTS idx_reportes_fecha ON reportes(fecha_hora DESC);
    CREATE INDEX IF NOT EXISTS idx_reportes_pdf_status ON reportes(pdf_status);

    CREATE TABLE IF NOT EXISTS usuarios (
      id SERIAL PRIMARY KEY,
      nombre TEXT NOT NULL,
      rol TEXT NOT NULL CHECK (rol IN ('admin', 'consulta')),
      api_key_hash TEXT NOT NULL UNIQUE,
      activo BOOLEAN NOT NULL DEFAULT TRUE,
      creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS prompts (
      clave TEXT PRIMARY KEY,
      contenido TEXT NOT NULL,
      actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      actualizado_por INTEGER REFERENCES usuarios(id)
    );
  `);
}

async function seedAdmin(hashApiKey) {
  const count = await queryOne("SELECT COUNT(*)::int AS n FROM usuarios");
  if (count && count.n > 0) {
    return null;
  }

  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    return null;
  }

  const hash = hashApiKey(apiKey);
  const row = await queryOne(
    `INSERT INTO usuarios (nombre, rol, api_key_hash, activo)
     VALUES ($1, 'admin', $2, TRUE)
     RETURNING id, nombre, rol`,
    ["Administrador", hash]
  );
  return row;
}

async function seedPrompt() {
  const existing = await queryOne(
    "SELECT clave FROM prompts WHERE clave = $1",
    ["reporte_ejecutivo"]
  );
  if (existing) {
    return false;
  }

  const promptPath = path.join(__dirname, "..", "prompts", "reporte_ejecutivo.txt");
  if (!fs.existsSync(promptPath)) {
    console.warn("No se encontro prompts/reporte_ejecutivo.txt para seed");
    return false;
  }

  const contenido = fs.readFileSync(promptPath, "utf8");
  await query(
    `INSERT INTO prompts (clave, contenido) VALUES ($1, $2)`,
    ["reporte_ejecutivo", contenido]
  );
  return true;
}

async function markInterruptedGenerations() {
  await query(
    `UPDATE reportes
     SET pdf_status = 'error',
         pdf_error = 'Interrumpido por reinicio del backend'
     WHERE pdf_status = 'generando'`
  );
}

async function initDb({ hashApiKey } = {}) {
  await ensureSchema();
  if (typeof hashApiKey === "function") {
    await seedAdmin(hashApiKey);
  }
  await seedPrompt();
  await markInterruptedGenerations();
}

async function closePool() {
  await pool.end();
}

module.exports = {
  pool,
  query,
  queryOne,
  queryAll,
  ensureSchema,
  seedAdmin,
  seedPrompt,
  markInterruptedGenerations,
  initDb,
  closePool,
};
