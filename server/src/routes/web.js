const express = require("express");
const path = require("path");
const fs = require("fs");
const multer = require("multer");
const db = require("../db");
const { checkApiKey, requireSession, requireCsrf } = require("../auth");
const { encolarGeneracion } = require("../services/pdfGenerator");

const router = express.Router();

const PDF_DIR = path.join(__dirname, "..", "..", "data", "pdfs");
fs.mkdirSync(PDF_DIR, { recursive: true });

// :id solo puede ser un entero positivo - evita path traversal en los nombres
// de archivo de PDF (que se derivan directamente de este parametro).
router.param("id", (req, res, next, id) => {
  if (!/^[0-9]+$/.test(id)) {
    return res.status(400).send("id invalido");
  }
  next();
});

function sanitizeSegment(value) {
  return String(value).replace(/[^A-Za-z0-9._-]/g, "_");
}

const pdfUpload = multer({
  storage: multer.memoryStorage(),
  fileFilter: (req, file, cb) => {
    cb(null, file.mimetype === "application/pdf");
  },
  limits: { fileSize: 25 * 1024 * 1024 },
});

router.get("/login", (req, res) => {
  res.render("login", { error: null });
});

router.post("/login", express.urlencoded({ extended: false }), (req, res) => {
  const { api_key } = req.body;
  if (checkApiKey(api_key)) {
    req.session.authenticated = true;
    return res.redirect("/dashboard");
  }
  res.status(401).render("login", { error: "API key invalida" });
});

router.post(
  "/logout",
  express.urlencoded({ extended: false }),
  requireSession,
  requireCsrf,
  (req, res) => {
    req.session.destroy(() => res.redirect("/login"));
  }
);

router.get("/dashboard", requireSession, (req, res) => {
  const equipoFiltro = req.query.equipo || "";
  const equipos = db
    .prepare("SELECT DISTINCT equipo FROM reportes ORDER BY equipo")
    .all()
    .map((r) => r.equipo);

  const reportes = equipoFiltro
    ? db
        .prepare(
          "SELECT id, equipo, fecha_hora, pdf_path, pdf_status, pdf_error FROM reportes WHERE equipo = ? ORDER BY fecha_hora DESC"
        )
        .all(equipoFiltro)
    : db
        .prepare(
          "SELECT id, equipo, fecha_hora, pdf_path, pdf_status, pdf_error FROM reportes ORDER BY fecha_hora DESC"
        )
        .all();

  res.render("dashboard", { equipos, reportes, equipoFiltro });
});

function descargarTxt(campo, nombreArchivo) {
  return (req, res) => {
    const row = db
      .prepare(`SELECT ${campo} AS contenido, equipo, fecha_hora FROM reportes WHERE id = ?`)
      .get(req.params.id);
    if (!row || row.contenido === null) {
      return res.status(404).send("Reporte no encontrado");
    }
    const safeName = `${sanitizeSegment(nombreArchivo)}_${sanitizeSegment(row.equipo)}_${req.params.id}.txt`;
    res.type("text/plain").attachment(safeName).send(row.contenido);
  };
}

router.get("/reportes/:id/sistema", requireSession, descargarTxt("reporte_sistema", "Sistema"));
router.get("/reportes/:id/red", requireSession, descargarTxt("reporte_red", "Red"));
router.get("/reportes/:id/logs", requireSession, descargarTxt("reporte_logs", "Logs"));

router.post(
  "/reportes/:id/generar-pdf",
  express.urlencoded({ extended: false }),
  requireSession,
  requireCsrf,
  (req, res) => {
    encolarGeneracion(req.params.id);
    res.redirect("/dashboard");
  }
);

router.post(
  "/reportes/:id/pdf",
  requireSession,
  pdfUpload.single("pdf"),
  requireCsrf,
  (req, res) => {
    if (!req.file) {
      return res.status(400).send("Archivo invalido, debe ser un PDF");
    }
    const row = db.prepare("SELECT pdf_status FROM reportes WHERE id = ?").get(req.params.id);
    if (row && row.pdf_status === "generando") {
      return res
        .status(409)
        .send("PDF en generacion, espere a que termine antes de subir uno manualmente");
    }
    fs.writeFileSync(path.join(PDF_DIR, `${req.params.id}.pdf`), req.file.buffer);
    db.prepare("UPDATE reportes SET pdf_path = ?, pdf_status = 'listo', pdf_error = NULL WHERE id = ?").run(
      `${req.params.id}.pdf`,
      req.params.id
    );
    res.redirect("/dashboard");
  }
);

router.get("/reportes/:id/pdf", requireSession, (req, res) => {
  const row = db.prepare("SELECT pdf_path FROM reportes WHERE id = ?").get(req.params.id);
  if (!row || !row.pdf_path) {
    return res.status(404).send("No hay PDF para este reporte");
  }
  // Defensa en profundidad: aunque pdf_path lo genera el propio servidor,
  // confirmamos que la ruta resuelta sigue dentro de PDF_DIR antes de servirla.
  const resolvedDir = path.resolve(PDF_DIR) + path.sep;
  const dest = path.resolve(PDF_DIR, row.pdf_path);
  if (!dest.startsWith(resolvedDir)) {
    return res.status(400).send("Ruta de archivo invalida");
  }
  res.download(dest);
});

module.exports = router;
