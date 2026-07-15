import { useEffect, useState } from "react";
import { useAuth } from "../auth";
import * as api from "../api";

export default function UsuariosPage() {
  const { user } = useAuth();
  const [rows, setRows] = useState([]);
  const [nombre, setNombre] = useState("");
  const [rol, setRol] = useState("consulta");
  const [error, setError] = useState("");
  const [createdKey, setCreatedKey] = useState("");
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    setError("");
    try {
      setRows(await api.fetchUsuarios(user.token));
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [user.token]);

  async function onCreate(e) {
    e.preventDefault();
    setCreatedKey("");
    try {
      const created = await api.createUsuario(user.token, { nombre, rol });
      setCreatedKey(created.api_key);
      setNombre("");
      setRol("consulta");
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function onToggle(row) {
    try {
      await api.patchUsuario(user.token, row.id, { activo: !row.activo });
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function onRegen(id) {
    try {
      const updated = await api.regenerarKey(user.token, id);
      setCreatedKey(updated.api_key);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  async function onDelete(id) {
    if (!confirm("¿Eliminar este usuario?")) return;
    try {
      await api.deleteUsuario(user.token, id);
      await load();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <div className="page">
      <header className="page-header">
        <div>
          <h1>Usuarios</h1>
          <p className="muted">API keys por rol admin / consulta</p>
        </div>
      </header>

      <form className="panel form-grid" onSubmit={onCreate}>
        <label>
          Nombre
          <input
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
            required
          />
        </label>
        <label>
          Rol
          <select value={rol} onChange={(e) => setRol(e.target.value)}>
            <option value="consulta">consulta</option>
            <option value="admin">admin</option>
          </select>
        </label>
        <button className="btn btn-primary" type="submit">
          Crear usuario
        </button>
      </form>

      {createdKey && (
        <div className="alert alert-ok">
          API key (copiala ahora, no se vuelve a mostrar):
          <code className="key-reveal">{createdKey}</code>
        </div>
      )}
      {error && <div className="alert alert-danger">{error}</div>}
      {loading && <p className="muted">Cargando…</p>}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Nombre</th>
              <th>Rol</th>
              <th>Activo</th>
              <th>Creado</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id}>
                <td>{row.id}</td>
                <td>{row.nombre}</td>
                <td>
                  <span className="badge badge-pending">{row.rol}</span>
                </td>
                <td>{row.activo ? "si" : "no"}</td>
                <td className="mono muted">
                  {row.creado_en
                    ? new Date(row.creado_en).toLocaleString()
                    : "—"}
                </td>
                <td className="actions">
                  <button
                    type="button"
                    className="btn btn-ghost"
                    onClick={() => onToggle(row)}
                  >
                    {row.activo ? "Desactivar" : "Activar"}
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() => onRegen(row.id)}
                  >
                    Regenerar key
                  </button>
                  <button
                    type="button"
                    className="btn btn-danger"
                    onClick={() => onDelete(row.id)}
                  >
                    Eliminar
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
