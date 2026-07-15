const express = require("express");
const db = require("../db");
const {
  requireJwt,
  requireRole,
  hashApiKey,
  generateApiKey,
} = require("../auth");

const router = express.Router();

router.use(requireJwt, requireRole("admin"));

router.get("/", async (req, res) => {
  try {
    const rows = await db.queryAll(
      `SELECT id, nombre, rol, activo, creado_en
       FROM usuarios
       ORDER BY id ASC`
    );
    return res.json(rows);
  } catch (error) {
    console.error("GET /usuarios:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

router.post("/", async (req, res) => {
  try {
    const { nombre, rol } = req.body || {};
    if (!nombre || !String(nombre).trim()) {
      return res.status(400).json({ error: "Falta nombre" });
    }
    if (rol !== "admin" && rol !== "consulta") {
      return res.status(400).json({ error: "rol debe ser admin o consulta" });
    }

    const apiKey = generateApiKey();
    const row = await db.queryOne(
      `INSERT INTO usuarios (nombre, rol, api_key_hash, activo)
       VALUES ($1, $2, $3, TRUE)
       RETURNING id, nombre, rol, activo, creado_en`,
      [String(nombre).trim(), rol, hashApiKey(apiKey)]
    );

    return res.status(201).json({ ...row, api_key: apiKey });
  } catch (error) {
    console.error("POST /usuarios:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

router.patch("/:id", async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ error: "id invalido" });
    }

    const { nombre, rol, activo } = req.body || {};
    const current = await db.queryOne(
      "SELECT id, nombre, rol, activo FROM usuarios WHERE id = $1",
      [id]
    );
    if (!current) {
      return res.status(404).json({ error: "Usuario no encontrado" });
    }

    const nextNombre =
      nombre !== undefined ? String(nombre).trim() : current.nombre;
    const nextRol = rol !== undefined ? rol : current.rol;
    const nextActivo = activo !== undefined ? Boolean(activo) : current.activo;

    if (!nextNombre) {
      return res.status(400).json({ error: "nombre invalido" });
    }
    if (nextRol !== "admin" && nextRol !== "consulta") {
      return res.status(400).json({ error: "rol debe ser admin o consulta" });
    }

    if (current.rol === "admin" && (nextRol !== "admin" || !nextActivo)) {
      const admins = await db.queryOne(
        `SELECT COUNT(*)::int AS n FROM usuarios
         WHERE rol = 'admin' AND activo = TRUE AND id <> $1`,
        [id]
      );
      if (!admins || admins.n < 1) {
        return res
          .status(400)
          .json({ error: "Debe quedar al menos un admin activo" });
      }
    }

    const row = await db.queryOne(
      `UPDATE usuarios
       SET nombre = $1, rol = $2, activo = $3
       WHERE id = $4
       RETURNING id, nombre, rol, activo, creado_en`,
      [nextNombre, nextRol, nextActivo, id]
    );
    return res.json(row);
  } catch (error) {
    console.error("PATCH /usuarios/:id:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

router.post("/:id/regenerar-key", async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ error: "id invalido" });
    }

    const current = await db.queryOne(
      "SELECT id FROM usuarios WHERE id = $1",
      [id]
    );
    if (!current) {
      return res.status(404).json({ error: "Usuario no encontrado" });
    }

    const apiKey = generateApiKey();
    const row = await db.queryOne(
      `UPDATE usuarios SET api_key_hash = $1 WHERE id = $2
       RETURNING id, nombre, rol, activo, creado_en`,
      [hashApiKey(apiKey), id]
    );
    return res.json({ ...row, api_key: apiKey });
  } catch (error) {
    console.error("POST /usuarios/:id/regenerar-key:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ error: "id invalido" });
    }

    if (req.user.id === id) {
      return res.status(400).json({ error: "No puedes eliminar tu propio usuario" });
    }

    const current = await db.queryOne(
      "SELECT id, rol, activo FROM usuarios WHERE id = $1",
      [id]
    );
    if (!current) {
      return res.status(404).json({ error: "Usuario no encontrado" });
    }

    if (current.rol === "admin" && current.activo) {
      const admins = await db.queryOne(
        `SELECT COUNT(*)::int AS n FROM usuarios
         WHERE rol = 'admin' AND activo = TRUE AND id <> $1`,
        [id]
      );
      if (!admins || admins.n < 1) {
        return res
          .status(400)
          .json({ error: "Debe quedar al menos un admin activo" });
      }
    }

    await db.query("DELETE FROM usuarios WHERE id = $1", [id]);
    return res.status(204).send();
  } catch (error) {
    console.error("DELETE /usuarios/:id:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

module.exports = router;
