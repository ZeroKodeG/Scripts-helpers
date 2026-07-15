import { NavLink, Outlet } from "react-router-dom";
import { useAuth } from "../auth";

export default function Layout() {
  const { user, isAdmin, logout } = useAuth();

  return (
    <div className="app-shell">
      <div className="top-strip" />
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">AUDIT</span>
          <div>
            <strong>Centro de auditoria</strong>
            <p>Reportes de servidores</p>
          </div>
        </div>
        <nav className="nav">
          <NavLink to="/" end>
            Reportes
          </NavLink>
          {isAdmin && <NavLink to="/usuarios">Usuarios</NavLink>}
          {isAdmin && <NavLink to="/prompt">Prompt</NavLink>}
        </nav>
        <div className="user-chip">
          <span>
            {user?.nombre} · {user?.rol}
          </span>
          <button type="button" className="btn btn-ghost" onClick={logout}>
            Salir
          </button>
        </div>
      </header>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
