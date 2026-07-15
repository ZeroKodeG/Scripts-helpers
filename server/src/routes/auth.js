const express = require("express");
const {
  findUserByApiKey,
  signToken,
  requireJwt,
} = require("../auth");

const router = express.Router();

router.post("/login", async (req, res) => {
  try {
    const apiKey = req.body && req.body.api_key;
    const user = await findUserByApiKey(apiKey);
    if (!user || !user.activo) {
      return res.status(401).json({ error: "API key invalida" });
    }
    const token = signToken(user);
    return res.json({
      token,
      rol: user.rol,
      nombre: user.nombre,
      id: user.id,
    });
  } catch (error) {
    console.error("POST /auth/login:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

router.get("/me", requireJwt, async (req, res) => {
  return res.json({
    id: req.user.id,
    nombre: req.user.nombre,
    rol: req.user.rol,
  });
});

module.exports = router;
