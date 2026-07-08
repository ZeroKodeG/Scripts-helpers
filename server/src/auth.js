const crypto = require("crypto");

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function checkApiKey(candidate) {
  const expected = process.env.API_KEY;
  if (!expected || !candidate) return false;
  return safeEqual(candidate, expected);
}

// Para el script cliente: exige header X-API-Key.
function requireApiKey(req, res, next) {
  const candidate = req.get("X-API-Key");
  if (!checkApiKey(candidate)) {
    return res.status(401).json({ error: "API key invalida o faltante" });
  }
  next();
}

// Para la web: exige sesion iniciada (via /login). De paso genera un token
// CSRF por sesion (si no existe aun) y lo expone a las vistas.
function requireSession(req, res, next) {
  if (req.session && req.session.authenticated) {
    if (!req.session.csrfToken) {
      req.session.csrfToken = crypto.randomBytes(24).toString("hex");
    }
    res.locals.csrfToken = req.session.csrfToken;
    return next();
  }
  return res.redirect("/login");
}

// Para forms que cambian estado (logout, subida de PDF): compara el token
// del body contra el guardado en sesion. Requiere requireSession antes.
function requireCsrf(req, res, next) {
  const token = req.session && req.session.csrfToken;
  const candidate = req.body && req.body._csrf;
  if (!token || !candidate || !safeEqual(candidate, token)) {
    return res.status(403).send("Token CSRF invalido o faltante");
  }
  next();
}

module.exports = { checkApiKey, requireApiKey, requireSession, requireCsrf };
