import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth";

export default function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [apiKey, setApiKey] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function onSubmit(e) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(apiKey.trim());
      navigate("/", { replace: true });
    } catch (err) {
      setError(err.message || "No se pudo iniciar sesion");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <div className="top-strip" />
      <form className="login-card" onSubmit={onSubmit}>
        <p className="eyebrow">Auditoria</p>
        <h1>Acceso al dashboard</h1>
        <p className="muted">Ingresa tu API key de usuario.</p>
        <label>
          API key
          <input
            type="password"
            autoComplete="current-password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            required
          />
        </label>
        {error && <div className="alert alert-danger">{error}</div>}
        <button className="btn btn-primary" disabled={loading || !apiKey.trim()}>
          {loading ? "Entrando…" : "Entrar"}
        </button>
      </form>
    </div>
  );
}
