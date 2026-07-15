/**
 * Store in-memory compatible con createPdfGenerator / createPgStore.
 * Evita depender de Postgres o better-sqlite3 en tests unitarios.
 */
function createMemoryStore(seed = {}) {
  const reportes = new Map();
  let nextId = 1;
  let promptContenido = seed.promptContenido ?? null;

  if (seed.reporte) {
    const id = seed.reporte.id || nextId++;
    reportes.set(id, {
      id,
      equipo: seed.reporte.equipo || "SERVER1",
      fecha_hora: seed.reporte.fecha_hora || new Date().toISOString(),
      reporte_sistema: seed.reporte.reporte_sistema || "sistema",
      reporte_red: seed.reporte.reporte_red || "red",
      reporte_logs: seed.reporte.reporte_logs || "logs",
      pdf_status: seed.reporte.pdf_status || "pendiente",
      pdf_path: seed.reporte.pdf_path || null,
      pdf_error: seed.reporte.pdf_error || null,
      pdf_tokens_input: null,
      pdf_tokens_output: null,
      pdf_tokens_reasoning: null,
      pdf_tokens_total: null,
      pdf_tokens_cache_read: null,
      pdf_tokens_cache_write: null,
      pdf_cost_total: null,
    });
    nextId = Math.max(nextId, id + 1);
  } else if (seed.withDefaultReporte !== false) {
    reportes.set(1, {
      id: 1,
      equipo: "SERVER1",
      fecha_hora: new Date().toISOString(),
      reporte_sistema: "sistema",
      reporte_red: "red",
      reporte_logs: "logs",
      pdf_status: "pendiente",
      pdf_path: null,
      pdf_error: null,
      pdf_tokens_input: null,
      pdf_tokens_output: null,
      pdf_tokens_reasoning: null,
      pdf_tokens_total: null,
      pdf_tokens_cache_read: null,
      pdf_tokens_cache_write: null,
      pdf_cost_total: null,
    });
    nextId = 2;
  }

  return {
    async getReporte(id) {
      const row = reportes.get(Number(id));
      return row ? { ...row } : null;
    },
    async markGenerating(id) {
      const row = reportes.get(Number(id));
      if (!row) return;
      Object.assign(row, {
        pdf_status: "generando",
        pdf_error: null,
        pdf_tokens_input: null,
        pdf_tokens_output: null,
        pdf_tokens_reasoning: null,
        pdf_tokens_total: null,
        pdf_tokens_cache_read: null,
        pdf_tokens_cache_write: null,
        pdf_cost_total: null,
      });
    },
    async markReady(fileName, metrics, id) {
      const row = reportes.get(Number(id));
      if (!row) return;
      Object.assign(row, {
        pdf_path: fileName,
        pdf_status: "listo",
        pdf_error: null,
        ...metrics,
      });
    },
    async markError(message, metrics, id) {
      const row = reportes.get(Number(id));
      if (!row) return;
      Object.assign(row, {
        pdf_path: null,
        pdf_status: "error",
        pdf_error: message,
        ...metrics,
      });
    },
    async getPromptContenido() {
      return promptContenido;
    },
    // helpers de test
    getRow(id) {
      const row = reportes.get(Number(id));
      return row ? { ...row } : null;
    },
    setPdfPath(id, pdfPath) {
      const row = reportes.get(Number(id));
      if (row) row.pdf_path = pdfPath;
    },
    setPrompt(contenido) {
      promptContenido = contenido;
    },
  };
}

module.exports = { createMemoryStore };
