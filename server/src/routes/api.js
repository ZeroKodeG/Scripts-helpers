const express = require("express");
const multer = require("multer");
const db = require("../db");
const { requireApiKey } = require("../auth");

const upload = multer(); // solo se usa para leer campos de texto multipart, sin archivos

const router = express.Router();

router.use(requireApiKey);

// POST /api/reportes - sube los 3 reportes de una corrida de un equipo
router.post("/reportes", upload.none(), (req, res) => {
  const { equipo, reporte_sistema, reporte_red, reporte_logs } = req.body;

  if (!equipo) {
    return res.status(400).json({ error: "Falta el campo equipo" });
  }

  const stmt = db.prepare(`
    INSERT INTO reportes (equipo, reporte_sistema, reporte_red, reporte_logs)
    VALUES (?, ?, ?, ?)
  `);
  const info = stmt.run(
    equipo,
    reporte_sistema || null,
    reporte_red || null,
    reporte_logs || null
  );

  res.status(201).json({ id: info.lastInsertRowid });
});

// GET /api/equipos - lista de equipos distintos
router.get("/equipos", (req, res) => {
  const rows = db
    .prepare("SELECT DISTINCT equipo FROM reportes ORDER BY equipo")
    .all();
  res.json(rows.map((r) => r.equipo));
});

// GET /api/reportes?equipo=NOMBRE - lista de corridas, mas recientes primero
router.get("/reportes", (req, res) => {
  const { equipo } = req.query;
  const rows = equipo
    ? db
        .prepare(
          "SELECT id, equipo, fecha_hora, pdf_path FROM reportes WHERE equipo = ? ORDER BY fecha_hora DESC"
        )
        .all(equipo)
    : db
        .prepare(
          "SELECT id, equipo, fecha_hora, pdf_path FROM reportes ORDER BY fecha_hora DESC"
        )
        .all();
  res.json(rows);
});

module.exports = router;
