import { useCallback, useEffect, useMemo, useState } from "react";
import { useAuth } from "../auth";
import * as api from "../api";

export default function DashboardPage() {
  const { user, isAdmin } = useAuth();
  const [equipos, setEquipos] = useState([]);
  const [reportes, setReportes] = useState([]);
  const [equipo, setEquipo] = useState("");
  const [fechaDesde, setFechaDesde] = useState("");
  const [fechaHasta, setFechaHasta] = useState("");
  const [estadoPdf, setEstadoPdf] = useState("todos");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [eq, rows] = await Promise.all([
        api.fetchEquipos(user.token),
        api.fetchReportes(user.token, {
          equipo,
          fecha_desde: fechaDesde,
          fecha_hasta: fechaHasta,
          estado_pdf: estadoPdf,
        }),
      ]);
      setEquipos(eq);
      setReportes(rows);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [user.token, equipo, fechaDesde, fechaHasta, estadoPdf]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    const hasGenerating = reportes.some((r) => r.pdf_status === "generando");
    if (!hasGenerating) return undefined;
    const t = setInterval(load, 4000);
    return () => clearInterval(t);
  }, [reportes, load]);

  const stats = useMemo(() => {
    return {
      equipos: equipos.length,
      total: reportes.length,
      listos: reportes.filter((r) => r.pdf_status === "listo").length,
      generando: reportes.filter((r) => r.pdf_status === "generando").length,
      errores: reportes.filter((r) => r.pdf_status === "error").length,
    };
  }, [equipos, reportes]);

  async function onGenerar(id) {
    try {
      await api.generarPdf(user.token, id);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function onUpload(id, file) {
    if (!file) return;
    try {
      await api.uploadPdf(user.token, id, file);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Reportes de servidores</h1>
          <p className="muted">Historial de auditorias por equipo</p>
        </div>
      </header>

      <section className="stats">
        <article>
          <span>Equipos</span>
          <strong>{stats.equipos}</strong>
        </article>
        <article>
          <span>Corridas</span>
          <strong>{stats.total}</strong>
        </article>
        <article>
          <span>PDF listos</span>
          <strong>{stats.listos}</strong>
        </article>
        <article>
          <span>Generando</span>
          <strong>{stats.generando}</strong>
        </article>
        <article>
          <span>Errores</span>
          <strong>{stats.errores}</strong>
        </article>
      </section>

      <form
        className="toolbar"
        onSubmit={(e) => {
          e.preventDefault();
          load();
        }}
      >
        <label>
          Equipo
          <select value={equipo} onChange={(e) => setEquipo(e.target.value)}>
            <option value="">Todos los equipos</option>
            {equipos.map((eq) => (
              <option key={eq} value={eq}>
                {eq}
              </option>
            ))}
          </select>
        </label>
        <label>
          Desde
          <input
            type="date"
            value={fechaDesde}
            onChange={(e) => setFechaDesde(e.target.value)}
          />
        </label>
        <label>
          Hasta
          <input
            type="date"
            value={fechaHasta}
            onChange={(e) => setFechaHasta(e.target.value)}
          />
        </label>
        <label>
          Estado PDF
          <select
            value={estadoPdf}
            onChange={(e) => setEstadoPdf(e.target.value)}
          >
            <option value="todos">Todos</option>
            <option value="generados">Generados</option>
            <option value="pendientes">Pendientes</option>
          </select>
        </label>
        <button type="submit" className="btn btn-secondary">
          Filtrar
        </button>
      </form>

      {error && <div className="alert alert-danger">{error}</div>}
      {loading && <p className="muted">Cargando reportes…</p>}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Equipo</th>
              <th>Fecha</th>
              <th>PDF</th>
              <th>Tokens / costo</th>
              <th>Reportes</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {reportes.map((r) => (
              <tr key={r.id}>
                <td>
                  <strong>{r.equipo}</strong>
                </td>
                <td className="mono">{r.fecha_hora_local || r.fecha_hora}</td>
                <td>
                  <StatusBadge status={r.pdf_status} error={r.pdf_error} />
                </td>
                <td className="mono muted">
                  {r.pdf_tokens_total != null
                    ? `${r.pdf_tokens_total} tok`
                    : "—"}
                  {r.pdf_cost_total_display
                    ? ` · $${r.pdf_cost_total_display}`
                    : ""}
                </td>
                <td className="actions">
                  <button
                    type="button"
                    className="btn btn-ghost"
                    onClick={() =>
                      api.downloadWithAuth(
                        user.token,
                        `/api/reportes/${r.id}/sistema`,
                        "Sistema.txt"
                      )
                    }
                  >
                    Sistema
                  </button>
                  <button
                    type="button"
                    className="btn btn-ghost"
                    onClick={() =>
                      api.downloadWithAuth(
                        user.token,
                        `/api/reportes/${r.id}/red`,
                        "Red.txt"
                      )
                    }
                  >
                    Red
                  </button>
                  <button
                    type="button"
                    className="btn btn-ghost"
                    onClick={() =>
                      api.downloadWithAuth(
                        user.token,
                        `/api/reportes/${r.id}/logs`,
                        "Logs.txt"
                      )
                    }
                  >
                    Logs
                  </button>
                </td>
                <td className="actions">
                  {r.pdf_status === "listo" && r.pdf_path && (
                    <button
                      type="button"
                      className="btn btn-primary"
                      onClick={() =>
                        api.downloadWithAuth(
                          user.token,
                          `/api/reportes/${r.id}/pdf`,
                          `${r.equipo}.pdf`
                        )
                      }
                    >
                      Descargar PDF
                    </button>
                  )}
                  {isAdmin && r.pdf_status !== "generando" && (
                    <button
                      type="button"
                      className="btn btn-secondary"
                      onClick={() => onGenerar(r.id)}
                    >
                      Generar PDF
                    </button>
                  )}
                  {isAdmin && r.pdf_status !== "generando" && (
                    <label className="btn btn-ghost file-btn">
                      Subir PDF
                      <input
                        type="file"
                        accept="application/pdf"
                        hidden
                        onChange={(e) => {
                          onUpload(r.id, e.target.files?.[0]);
                          e.target.value = "";
                        }}
                      />
                    </label>
                  )}
                  {r.pdf_status === "generando" && (
                    <span className="muted">En cola…</span>
                  )}
                </td>
              </tr>
            ))}
            {!loading && reportes.length === 0 && (
              <tr>
                <td colSpan={6} className="muted">
                  No hay reportes con estos filtros.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function StatusBadge({ status, error }) {
  const map = {
    listo: ["ok", "Generado"],
    generando: ["pending", "Generando"],
    pendiente: ["pending", "Pendiente"],
    error: ["danger", "Error"],
  };
  const [tone, label] = map[status] || ["pending", status];
  return (
    <span className={`badge badge-${tone}`} title={error || ""}>
      {label}
    </span>
  );
}
