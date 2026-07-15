import { useEffect, useState } from "react";
import { useAuth } from "../auth";
import * as api from "../api";

export default function PromptPage() {
  const { user } = useAuth();
  const [contenido, setContenido] = useState("");
  const [meta, setMeta] = useState(null);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      setLoading(true);
      try {
        const row = await api.fetchPrompt(user.token);
        setContenido(row.contenido || "");
        setMeta(row);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    load();
  }, [user.token]);

  async function onSave(e) {
    e.preventDefault();
    setSaved(false);
    setError("");
    try {
      const row = await api.savePrompt(user.token, contenido);
      setMeta(row);
      setSaved(true);
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Prompt ejecutivo</h1>
          <p className="muted">
            Texto usado por opencode para normalizar el reporte PDF
          </p>
        </div>
      </header>

      {loading && <p className="muted">Cargando…</p>}
      {error && <div className="alert alert-danger">{error}</div>}
      {saved && <div className="alert alert-ok">Prompt guardado.</div>}

      <form className="panel" onSubmit={onSave}>
        {meta?.actualizado_en && (
          <p className="muted">
            Ultima actualizacion:{" "}
            {new Date(meta.actualizado_en).toLocaleString()}
          </p>
        )}
        <textarea
          className="prompt-editor"
          rows={24}
          value={contenido}
          onChange={(e) => setContenido(e.target.value)}
          spellCheck={false}
        />
        <div className="form-actions">
          <button className="btn btn-primary" type="submit">
            Guardar prompt
          </button>
        </div>
      </form>
    </div>
  );
}
