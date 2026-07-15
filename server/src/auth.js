const crypto = require("crypto");
const jwt = require("jsonwebtoken");
const db = require("./db");

const JWT_TTL = process.env.JWT_TTL || "8h";

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function hashApiKey(apiKey) {
  return crypto.createHash("sha256").update(String(apiKey), "utf8").digest("hex");
}

function generateApiKey() {
  return crypto.randomBytes(32).toString("hex");
}

function getJwtSecret() {
  const secret = process.env.JWT_SECRET || process.env.SESSION_SECRET;
  if (!secret) {
    throw new Error("Falta JWT_SECRET (o SESSION_SECRET) en el entorno");
  }
  return secret;
}

function signToken(user) {
  return jwt.sign(
    { sub: user.id, rol: user.rol, nombre: user.nombre },
    getJwtSecret(),
    { expiresIn: JWT_TTL }
  );
}

function verifyToken(token) {
  return jwt.verify(token, getJwtSecret());
}

async function findUserByApiKey(apiKey) {
  if (!apiKey) return null;
  const hash = hashApiKey(apiKey);
  return db.queryOne(
    `SELECT id, nombre, rol, activo
     FROM usuarios
     WHERE api_key_hash = $1`,
    [hash]
  );
}

async function requireApiKey(req, res, next) {
  try {
    const candidate = req.get("X-API-Key");
    const user = await findUserByApiKey(candidate);
    if (!user || !user.activo) {
      return res.status(401).json({ error: "API key invalida o faltante" });
    }
    if (user.rol !== "admin") {
      return res.status(403).json({ error: "Se requiere rol admin para esta operacion" });
    }
    req.user = user;
    return next();
  } catch (error) {
    console.error("requireApiKey:", error);
    return res.status(500).json({ error: "Error de autenticacion" });
  }
}

function requireJwt(req, res, next) {
  try {
    const header = req.get("Authorization") || "";
    const match = header.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      return res.status(401).json({ error: "Token JWT faltante" });
    }
    const payload = verifyToken(match[1]);
    req.user = {
      id: payload.sub,
      rol: payload.rol,
      nombre: payload.nombre,
    };
    return next();
  } catch {
    return res.status(401).json({ error: "Token JWT invalido o expirado" });
  }
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.rol)) {
      return res.status(403).json({ error: "Permiso insuficiente" });
    }
    return next();
  };
}

module.exports = {
  safeEqual,
  hashApiKey,
  generateApiKey,
  signToken,
  verifyToken,
  findUserByApiKey,
  requireApiKey,
  requireJwt,
  requireRole,
};
