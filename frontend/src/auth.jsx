import { createContext, useContext, useEffect, useMemo, useState } from "react";
import * as api from "./api";

const AuthContext = createContext(null);
const STORAGE_KEY = "auditoria_auth";

export function AuthProvider({ children }) {
  const [auth, setAuth] = useState(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  });
  const [booting, setBooting] = useState(Boolean(auth?.token));

  useEffect(() => {
    let cancelled = false;
    async function verify() {
      if (!auth?.token) {
        setBooting(false);
        return;
      }
      try {
        const me = await api.getMe(auth.token);
        if (!cancelled) {
          const next = { ...auth, ...me };
          setAuth(next);
          localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
        }
      } catch {
        if (!cancelled) {
          setAuth(null);
          localStorage.removeItem(STORAGE_KEY);
        }
      } finally {
        if (!cancelled) setBooting(false);
      }
    }
    verify();
    return () => {
      cancelled = true;
    };
    // Solo al montar
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const value = useMemo(
    () => ({
      user: auth,
      booting,
      isAdmin: auth?.rol === "admin",
      async login(apiKey) {
        const data = await api.login(apiKey);
        const next = {
          token: data.token,
          id: data.id,
          nombre: data.nombre,
          rol: data.rol,
        };
        setAuth(next);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
        return next;
      },
      logout() {
        setAuth(null);
        localStorage.removeItem(STORAGE_KEY);
      },
    }),
    [auth, booting]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth fuera de AuthProvider");
  return ctx;
}
