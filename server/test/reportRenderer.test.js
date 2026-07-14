const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { runRenderer } = require("../src/services/reportRenderer");

test("runRenderer executes python script and produces output file", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "renderer-test-"));
  const scriptPath = path.join(root, "render.py");
  const inputPath = path.join(root, "input.json");
  const outputPath = path.join(root, "out.pdf");

  fs.writeFileSync(inputPath, "{}");
  fs.writeFileSync(
    scriptPath,
    [
      "import sys",
      "from pathlib import Path",
      "Path(sys.argv[2]).write_bytes(b'%PDF-1.4 fake pdf')",
      "print('ok')",
    ].join("\n")
  );

  const result = await runRenderer({ scriptPath, inputPath, outputPath, timeoutMs: 5000 });
  assert.equal(result.code, 0);
  assert.equal(fs.existsSync(outputPath), true);
});

test("renderer accepts reports with empty optional sections and mandatory final section only", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "renderer-sections-"));
  const scriptPath = path.join(process.cwd(), "scripts", "render_reporte_ejecutivo.py");
  const inputPath = path.join(root, "input.json");
  const outputPath = path.join(root, "out.pdf");

  fs.writeFileSync(
    inputPath,
    JSON.stringify(
      {
        metadata: {
          reportTitle: "Auditoria Tecnica de Seguridad - Servidor PR-XNET",
          reportId: "AUD-PR-XNET-20260709",
          organization: "Patrimonio",
          equipo: "PR-XNET",
          localDate: "2026-07-09",
          localDateTime: "2026-07-09 16:00:58",
          timeZone: "America/Monterrey",
        },
        sections: {
          resumen_ejecutivo: {
            title: "Resumen ejecutivo",
            summary: "Resumen corto",
            blocks: [],
          },
          hallazgos_y_recomendaciones: {
            title: "Hallazgos y recomendaciones",
            summary: "Cierre final",
            groups: {
              criticos: [
                {
                  severity: "Critico",
                  title: "Firewall deshabilitado",
                  evidence: "EnableFirewall = 0x0",
                  recommendation: "Activar firewall",
                },
              ],
              atencion: [],
              informativos: [],
            },
          },
        },
      },
      null,
      2
    )
  );

  const result = await runRenderer({ scriptPath, inputPath, outputPath, timeoutMs: 5000 });
  assert.equal(result.code, 0);
  assert.equal(fs.existsSync(outputPath), true);
});

test("renderer produces branded sections footer and table content", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "renderer-branding-"));
  const scriptPath = path.join(process.cwd(), "scripts", "render_reporte_ejecutivo.py");
  const inputPath = path.join(root, "input.json");
  const outputPath = path.join(root, "out.pdf");

  fs.writeFileSync(
    inputPath,
    JSON.stringify(
      {
        metadata: {
          reportTitle: "Auditoria Tecnica de Seguridad - Servidor PR-NOC01OCA",
          reportId: "PR-NOC01OCA-20260709",
          organization: "patrimonio.com",
          equipo: "PR-NOC01OCA",
          localDate: "2026-07-09",
          localDateTime: "2026-07-09 10:29:26",
          timeZone: "America/Monterrey",
        },
        sections: {
          resumen_ejecutivo: {
            title: "Resumen ejecutivo",
            summary: "Resumen de hallazgos principales.",
            blocks: ["Se detectaron servicios expuestos y hallazgos accionables."],
          },
          informacion_sistema: {
            title: "Informacion del sistema",
            summary: "Datos generales del servidor auditado.",
            tables: [
              {
                title: "Identificacion del servidor",
                rows: [
                  { Campo: "Equipo", Valor: "PR-NOC01OCA" },
                  { Campo: "Sistema operativo", Valor: "Windows Server 2019" },
                ],
              },
            ],
          },
          hallazgos_y_recomendaciones: {
            title: "Hallazgos y recomendaciones",
            summary: "Cierre final del reporte.",
            groups: {
              criticos: [
                {
                  severity: "Critico",
                  title: "RDP expuesto",
                  evidence: "Puerto 3389 en escucha sobre interfaces accesibles.",
                  recommendation: "Restringir RDP por origen y revisar firewall.",
                },
              ],
              atencion: [
                {
                  severity: "Atencion",
                  title: "WinRM expuesto",
                  evidence: "Puerto 5985 en escucha.",
                  recommendation: "Restringir acceso administrativo remoto.",
                },
              ],
              informativos: [
                {
                  severity: "Informativo",
                  title: "Conectividad al dominio",
                  evidence: "0% de perdida hacia el controlador cercano.",
                  recommendation: "Mantener monitoreo periodico.",
                },
              ],
            },
          },
        },
      },
      null,
      2
    )
  );

  const result = await runRenderer({ scriptPath, inputPath, outputPath, timeoutMs: 5000 });
  assert.equal(result.code, 0);

  const pdfText = fs.readFileSync(outputPath, "latin1");
  assert.match(pdfText, /Auditoria Tecnica de Seguridad - Servidor PR-NOC01OCA/);
  assert.match(pdfText, /Confidencial/);
  assert.match(pdfText, /Resumen ejecutivo/);
  assert.match(pdfText, /Informacion del sistema/);
  assert.match(pdfText, /Hallazgos y recomendaciones/);
  assert.match(pdfText, /Identificacion del servidor/);
  assert.match(pdfText, /Campo/);
  assert.match(pdfText, /Valor/);
  assert.match(pdfText, /Evidencia/);
  assert.match(pdfText, /Recomendacion/);
  assert.match(pdfText, /Atencion/);
  assert.match(pdfText, /WinRM expuesto/);
});

test("renderer colors semantic statuses including Atencion in tables and findings", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "renderer-attn-"));
  const scriptPath = path.join(process.cwd(), "scripts", "render_reporte_ejecutivo.py");
  const inputPath = path.join(root, "input.json");
  const outputPath = path.join(root, "out.pdf");

  fs.writeFileSync(
    inputPath,
    JSON.stringify(
      {
        metadata: {
          reportTitle: "Auditoria Tecnica de Seguridad - Servidor DEMO-ATTN",
          reportId: "DEMO-ATTN-20260714",
          organization: "demo.local",
          equipo: "DEMO-ATTN",
          localDate: "2026-07-14",
          localDateTime: "2026-07-14 16:00:00",
          timeZone: "America/Monterrey",
        },
        sections: {
          resumen_ejecutivo: {
            title: "Resumen ejecutivo",
            summary: "Tabla de indicadores con estados semanticos.",
            tables: [
              {
                title: "Indicadores de riesgo",
                rows: [
                  { Indicador: "Firewall", Valor: "Off", Estado: "Critico" },
                  { Indicador: "RDP", Valor: "3389", Estado: "Atencion" },
                  { Indicador: "Dominio", Valor: "OK", Estado: "OK" },
                ],
              },
            ],
          },
          hallazgos_y_recomendaciones: {
            title: "Hallazgos y recomendaciones",
            summary: "Incluye severidad Atencion.",
            groups: {
              criticos: [],
              atencion: [
                {
                  severity: "Atencion",
                  title: "RDP sin restriccion de origen",
                  evidence: "Puerto 3389 en escucha.",
                  recommendation: "Limitar origenes permitidos.",
                },
              ],
              informativos: [],
            },
          },
        },
      },
      null,
      2
    )
  );

  const result = await runRenderer({ scriptPath, inputPath, outputPath, timeoutMs: 5000 });
  assert.equal(result.code, 0);
  assert.equal(fs.existsSync(outputPath), true);

  const pdfText = fs.readFileSync(outputPath, "latin1");
  assert.match(pdfText, /Indicadores de riesgo/);
  assert.match(pdfText, /Critico/);
  assert.match(pdfText, /Atencion/);
  assert.match(pdfText, /RDP sin restriccion de origen/);
});
