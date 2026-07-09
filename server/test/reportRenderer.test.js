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
