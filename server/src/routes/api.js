const express = require("express");
const db = require("../db");
const { requireJwt } = require("../auth");
const authRoutes = require("./auth");
const reportesRoutes = require("./reportes");
const usuariosRoutes = require("./usuarios");
const promptsRoutes = require("./prompts");

const router = express.Router();

router.use("/auth", authRoutes);
router.use("/reportes", reportesRoutes);
router.use("/usuarios", usuariosRoutes);
router.use("/prompts", promptsRoutes);

router.get("/equipos", requireJwt, async (req, res) => {
  try {
    const rows = await db.queryAll(
      "SELECT DISTINCT equipo FROM reportes ORDER BY equipo"
    );
    return res.json(rows.map((r) => r.equipo));
  } catch (error) {
    console.error("GET /equipos:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

module.exports = router;
