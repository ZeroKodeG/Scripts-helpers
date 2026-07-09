const test = require("node:test");
const assert = require("node:assert/strict");

const {
  SECTION_ORDER,
  FINAL_SECTION_KEY,
  validateNormalizedReport,
} = require("../src/services/reportSchema");

test("section order always ends with hallazgos_y_recomendaciones", () => {
  assert.equal(SECTION_ORDER.at(-1), FINAL_SECTION_KEY);
  assert.deepEqual(SECTION_ORDER, [
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
  ]);
});

test("validateNormalizedReport accepts canonical report with mandatory final section", () => {
  const report = {
    metadata: {
      reportTitle: "Auditoria Tecnica de Seguridad - Servidor PR-APPNET",
      reportId: "AUD-TI-PRAPPNET-20260709",
      organization: "Patrimonio",
      equipo: "PR-APPNET",
      localDate: "2026-07-09",
      localDateTime: "2026-07-09 15:36:13",
      timeZone: "America/Monterrey",
    },
    sections: {
      resumen_ejecutivo: {
        title: "Resumen ejecutivo",
        summary: "Hallazgos relevantes detectados durante la auditoria.",
        blocks: [],
      },
      hallazgos_y_recomendaciones: {
        title: "Hallazgos y recomendaciones",
        summary: "Consolidado final de hallazgos accionables.",
        groups: {
          criticos: [
            {
              severity: "Critico",
              title: "Firewall deshabilitado",
              evidence: "EnableFirewall = 0x0 en StandardProfile y PublicProfile.",
              recommendation: "Activar el firewall y restringir accesos remotos.",
            },
          ],
          atencion: [],
          informativos: [],
        },
      },
    },
  };

  assert.doesNotThrow(() => validateNormalizedReport(report));
});

test("validateNormalizedReport rejects report without mandatory final section", () => {
  const report = {
    metadata: {
      reportTitle: "Titulo",
      reportId: "ID",
      organization: "Org",
      equipo: "EQ",
      localDate: "2026-07-09",
      localDateTime: "2026-07-09 15:36:13",
      timeZone: "America/Monterrey",
    },
    sections: {},
  };

  assert.throws(() => validateNormalizedReport(report), /seccion final obligatoria/i);
});

test("validateNormalizedReport rejects hallazgo without evidence", () => {
  const report = {
    metadata: {
      reportTitle: "Titulo",
      reportId: "ID",
      organization: "Org",
      equipo: "EQ",
      localDate: "2026-07-09",
      localDateTime: "2026-07-09 15:36:13",
      timeZone: "America/Monterrey",
    },
    sections: {
      hallazgos_y_recomendaciones: {
        title: "Hallazgos y recomendaciones",
        summary: "Resumen",
        groups: {
          criticos: [
            {
              severity: "Critico",
              title: "Firewall off",
              evidence: "",
              recommendation: "Activar firewall",
            },
          ],
          atencion: [],
          informativos: [],
        },
      },
    },
  };

  assert.throws(() => validateNormalizedReport(report), /evidence es obligatorio/i);
});
