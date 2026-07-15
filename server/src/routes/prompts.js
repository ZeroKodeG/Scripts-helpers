const express = require("express");
const db = require("../db");
const { requireJwt, requireRole } = require("../auth");

const router = express.Router();
const CLAVE = "reporte_ejecutivo";

router.use(requireJwt, requireRole("admin"));

router.get("/reporte_ejecutivo", async (req, res) => {
  try {
    const row = await db.queryOne(
      `SELECT clave, contenido, actualizado_en, actualizado_por
       FROM prompts WHERE clave = $1`,
      [CLAVE]
    );
    if (!row) {
      return res.status(404).json({ error: "Prompt no encontrado" });
    }
    return res.json(row);
  } catch (error) {
    console.error("GET /prompts/reporte_ejecutivo:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

router.put("/reporte_ejecutivo", async (req, res) => {
  try {
    const contenido = req.body && req.body.contenido;
    if (typeof contenido !== "string" || !contenido.trim()) {
      return res.status(400).json({ error: "contenido es requerido" });
    }

    const row = await db.queryOne(
      `INSERT INTO prompts (clave, contenido, actualizado_en, actualizado_por)
       VALUES ($1, $2, NOW(), $3)
       ON CONFLICT (clave) DO UPDATE
         SET contenido = EXCLUDED.contenido,
             actualizado_en = NOW(),
             actualizado_por = EXCLUDED.actualizado_por
       RETURNING clave, contenido, actualizado_en, actualizado_por`,
      [CLAVE, contenido, req.user.id]
    );
    return res.json(row);
  } catch (error) {
    console.error("PUT /prompts/reporte_ejecutivo:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

module.exports = router;
