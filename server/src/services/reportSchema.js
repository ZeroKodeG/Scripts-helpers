const SECTION_ORDER = [
  "resumen_ejecutivo",
  "informacion_sistema",
  "cuentas_privilegios",
  "politicas_seguridad",
  "configuracion_red",
  "superficie_exposicion",
  "recursos_y_servicios",
  "eventos_autenticacion",
  "errores_y_logs",
  "hallazgos_y_recomendaciones",
];

const FINAL_SECTION_KEY = "hallazgos_y_recomendaciones";
const ALLOWED_SEVERITIES = new Set(["Critico", "Atencion", "Informativo"]);

function assertNonEmptyString(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} es obligatorio`);
  }
}

function validateMetadata(metadata) {
  if (!metadata || typeof metadata !== "object") {
    throw new Error("metadata es obligatorio");
  }
  assertNonEmptyString(metadata.reportTitle, "metadata.reportTitle");
  assertNonEmptyString(metadata.reportId, "metadata.reportId");
  assertNonEmptyString(metadata.organization, "metadata.organization");
  assertNonEmptyString(metadata.equipo, "metadata.equipo");
  assertNonEmptyString(metadata.localDate, "metadata.localDate");
  assertNonEmptyString(metadata.localDateTime, "metadata.localDateTime");
  assertNonEmptyString(metadata.timeZone, "metadata.timeZone");
}

function validateHallazgo(item, path) {
  if (!item || typeof item !== "object") {
    throw new Error(`${path} debe ser un objeto`);
  }
  assertNonEmptyString(item.severity, `${path}.severity`);
  if (!ALLOWED_SEVERITIES.has(item.severity)) {
    throw new Error(`${path}.severity no es valido`);
  }
  assertNonEmptyString(item.title, `${path}.title`);
  assertNonEmptyString(item.evidence, `${path}.evidence`);
  assertNonEmptyString(item.recommendation, `${path}.recommendation`);
}

function validateFinalSection(section) {
  if (!section || typeof section !== "object") {
    throw new Error("sections.hallazgos_y_recomendaciones es obligatorio");
  }

  assertNonEmptyString(section.title, "sections.hallazgos_y_recomendaciones.title");
  assertNonEmptyString(section.summary, "sections.hallazgos_y_recomendaciones.summary");

  const groups = section.groups || {};
  for (const key of ["criticos", "atencion", "informativos"]) {
    if (!Array.isArray(groups[key])) {
      throw new Error(`sections.hallazgos_y_recomendaciones.groups.${key} debe ser arreglo`);
    }
    groups[key].forEach((item, index) => {
      validateHallazgo(item, `sections.hallazgos_y_recomendaciones.groups.${key}[${index}]`);
    });
  }
}

function validateNormalizedReport(report) {
  if (!report || typeof report !== "object") {
    throw new Error("El reporte normalizado debe ser un objeto");
  }

  validateMetadata(report.metadata);

  if (!report.sections || typeof report.sections !== "object") {
    throw new Error("sections es obligatorio");
  }

  for (const key of Object.keys(report.sections)) {
    if (!SECTION_ORDER.includes(key)) {
      throw new Error(`Seccion no permitida: ${key}`);
    }
  }

  if (!report.sections[FINAL_SECTION_KEY]) {
    throw new Error("Falta la seccion final obligatoria hallazgos_y_recomendaciones");
  }

  validateFinalSection(report.sections[FINAL_SECTION_KEY]);
  return report;
}

module.exports = {
  ALLOWED_SEVERITIES,
  FINAL_SECTION_KEY,
  SECTION_ORDER,
  validateNormalizedReport,
};
