const express = require("express");
const path = require("path");
const fs = require("fs");
const multer = require("multer");
const db = require("../db");
const { requireApiKey, requireJwt, requireRole } = require("../auth");
const { encolarGeneracion } = require("../services/pdfGenerator");
const {
  formatDateForFileName,
  formatDateTimeForDisplay,
} = require("../reportTime");

const router = express.Router();

const PDF_DIR = path.join(__dirname, "..", "..", "data", "pdfs");
fs.mkdirSync(PDF_DIR, { recursive: true });

const upload = multer({
  limits: {
    fieldSize: 20 * 1024 * 1024,
    fields: 10,
  },
});
const parseUrlEncoded = express.urlencoded({
  extended: false,
  limit: "20mb",
  parameterLimit: 10,
});

const pdfUpload = multer({
  storage: multer.memoryStorage(),
  fileFilter: (req, file, cb) => {
    cb(null, file.mimetype === "application/pdf");
  },
  limits: { fileSize: 25 * 1024 * 1024 },
});

router.param("id", (req, res, next, id) => {
  if (!/^[0-9]+$/.test(id)) {
    return res.status(400).json({ error: "id invalido" });
  }
  next();
});

function sanitizeSegment(value) {
  return String(value).replace(/[^A-Za-z0-9._-]/g, "_");
}

/** Postgres TEXT/UTF8 no admite NUL (0x00); los reportes de Windows a veces los traen. */
function scrubNulls(value) {
  if (value == null) return null;
  return String(value).replace(/\u0000/g, "");
}

function formatPdfCost(value) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric.toFixed(4) : null;
}

function buildReportesFilters(query) {
  const clauses = [];
  const params = [];

  if (query.equipo) {
    params.push(query.equipo);
    clauses.push(`equipo = $${params.length}`);
  }

  if (query.fecha_desde) {
    params.push(query.fecha_desde);
    clauses.push(`fecha_hora::date >= $${params.length}::date`);
  }

  if (query.fecha_hasta) {
    params.push(query.fecha_hasta);
    clauses.push(`fecha_hora::date <= $${params.length}::date`);
  }

  const estado = query.estado_pdf || "todos";
  if (estado === "generados") {
    clauses.push(`pdf_status = 'listo'`);
  } else if (estado === "pendientes") {
    clauses.push(`pdf_status IN ('pendiente', 'generando', 'error')`);
  }

  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  return { where, params };
}

// ---- Machine upload (X-API-Key admin) ----
router.post(
  "/",
  requireApiKey,
  parseUrlEncoded,
  upload.none(),
  async (req, res) => {
    try {
      const { equipo, reporte_sistema, reporte_red, reporte_logs } = req.body;

      if (!equipo) {
        return res.status(400).json({ error: "Falta el campo equipo" });
      }

      const row = await db.queryOne(
        `INSERT INTO reportes (equipo, reporte_sistema, reporte_red, reporte_logs)
         VALUES ($1, $2, $3, $4)
         RETURNING id`,
        [
          scrubNulls(equipo),
          scrubNulls(reporte_sistema) || null,
          scrubNulls(reporte_red) || null,
          scrubNulls(reporte_logs) || null,
        ]
      );

      return res.status(201).json({ id: row.id });
    } catch (error) {
      console.error("POST /reportes:", error);
      return res.status(500).json({ error: "Error interno" });
    }
  }
);

// ---- JWT authenticated routes ----
router.get("/", requireJwt, async (req, res) => {
  try {
    const { where, params } = buildReportesFilters(req.query);
    const rows = await db.queryAll(
      `SELECT id, equipo, fecha_hora, pdf_path, pdf_status, pdf_error,
              pdf_tokens_input, pdf_tokens_output, pdf_cost_total
       FROM reportes
       ${where}
       ORDER BY fecha_hora DESC`,
      params
    );

    return res.json(
      rows.map((reporte) => ({
        ...reporte,
        fecha_hora_local: formatDateTimeForDisplay(reporte.fecha_hora),
        pdf_cost_total_display: formatPdfCost(reporte.pdf_cost_total),
      }))
    );
  } catch (error) {
    console.error("GET /reportes:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

function descargarTxt(campo, nombreArchivo) {
  return async (req, res) => {
    try {
      const allowed = {
        reporte_sistema: true,
        reporte_red: true,
        reporte_logs: true,
      };
      if (!allowed[campo]) {
        return res.status(400).json({ error: "campo invalido" });
      }

      const row = await db.queryOne(
        `SELECT ${campo} AS contenido, equipo, fecha_hora FROM reportes WHERE id = $1`,
        [req.params.id]
      );
      if (!row || row.contenido === null) {
        return res.status(404).json({ error: "Reporte no encontrado" });
      }
      const safeName = `${sanitizeSegment(nombreArchivo)}_${sanitizeSegment(row.equipo)}_${req.params.id}.txt`;
      res.type("text/plain").attachment(safeName).send(row.contenido);
    } catch (error) {
      console.error(`GET /reportes/:id/${nombreArchivo}:`, error);
      return res.status(500).json({ error: "Error interno" });
    }
  };
}

router.get("/:id/sistema", requireJwt, descargarTxt("reporte_sistema", "Sistema"));
router.get("/:id/red", requireJwt, descargarTxt("reporte_red", "Red"));
router.get("/:id/logs", requireJwt, descargarTxt("reporte_logs", "Logs"));

router.post(
  "/:id/generar-pdf",
  requireJwt,
  requireRole("admin"),
  async (req, res) => {
    try {
      const queued = await encolarGeneracion(req.params.id);
      if (!queued) {
        return res.status(409).json({
          error: "No se pudo encolar (no existe o ya esta generando)",
        });
      }
      return res.json({ ok: true, status: "generando" });
    } catch (error) {
      console.error("POST /reportes/:id/generar-pdf:", error);
      return res.status(500).json({ error: "Error interno" });
    }
  }
);

router.post(
  "/:id/pdf",
  requireJwt,
  requireRole("admin"),
  pdfUpload.single("pdf"),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: "Archivo invalido, debe ser un PDF" });
      }
      const row = await db.queryOne(
        "SELECT pdf_status FROM reportes WHERE id = $1",
        [req.params.id]
      );
      if (!row) {
        return res.status(404).json({ error: "Reporte no encontrado" });
      }
      if (row.pdf_status === "generando") {
        return res.status(409).json({
          error:
            "PDF en generacion, espere a que termine antes de subir uno manualmente",
        });
      }

      fs.writeFileSync(
        path.join(PDF_DIR, `${req.params.id}.pdf`),
        req.file.buffer
      );
      await db.query(
        `UPDATE reportes
         SET pdf_path = $1, pdf_status = 'listo', pdf_error = NULL
         WHERE id = $2`,
        [`${req.params.id}.pdf`, req.params.id]
      );
      return res.json({ ok: true, pdf_path: `${req.params.id}.pdf` });
    } catch (error) {
      console.error("POST /reportes/:id/pdf:", error);
      return res.status(500).json({ error: "Error interno" });
    }
  }
);

router.get("/:id/pdf", requireJwt, async (req, res) => {
  try {
    const row = await db.queryOne(
      "SELECT pdf_path, equipo, fecha_hora FROM reportes WHERE id = $1",
      [req.params.id]
    );
    if (!row || !row.pdf_path) {
      return res.status(404).json({ error: "No hay PDF para este reporte" });
    }

    const resolvedDir = path.resolve(PDF_DIR) + path.sep;
    const dest = path.resolve(PDF_DIR, row.pdf_path);
    if (!dest.startsWith(resolvedDir)) {
      return res.status(400).json({ error: "Ruta de archivo invalida" });
    }
    const downloadName = `${sanitizeSegment(row.equipo || "reporte")}.${formatDateForFileName(row.fecha_hora)}.pdf`;
    return res.download(dest, downloadName);
  } catch (error) {
    console.error("GET /reportes/:id/pdf:", error);
    return res.status(500).json({ error: "Error interno" });
  }
});

module.exports = router;
module.exports.buildReportesFilters = buildReportesFilters;
