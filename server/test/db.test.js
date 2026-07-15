const test = require("node:test");
const assert = require("node:assert/strict");

process.env.NODE_ENV = "test";

const { buildReportesFilters } = require("../src/routes/reportes");
const { hashApiKey, generateApiKey } = require("../src/auth");

test("hashApiKey es determinista y generaApiKey produce keys largas", () => {
  assert.equal(hashApiKey("abc"), hashApiKey("abc"));
  assert.notEqual(hashApiKey("abc"), hashApiKey("xyz"));
  assert.equal(generateApiKey().length, 64);
});

test("buildReportesFilters combina equipo, fechas y estado_pdf", () => {
  const empty = buildReportesFilters({});
  assert.equal(empty.where, "");
  assert.deepEqual(empty.params, []);

  const generados = buildReportesFilters({
    equipo: "SRV1",
    fecha_desde: "2026-01-01",
    fecha_hasta: "2026-01-31",
    estado_pdf: "generados",
  });
  assert.match(generados.where, /equipo = \$1/);
  assert.match(generados.where, /fecha_hora::date >= \$2::date/);
  assert.match(generados.where, /fecha_hora::date <= \$3::date/);
  assert.match(generados.where, /pdf_status = 'listo'/);
  assert.deepEqual(generados.params, ["SRV1", "2026-01-01", "2026-01-31"]);

  const pendientes = buildReportesFilters({ estado_pdf: "pendientes" });
  assert.match(pendientes.where, /pdf_status IN \('pendiente', 'generando', 'error'\)/);
});
