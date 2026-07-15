const API_URL = (import.meta.env.VITE_API_URL || "").replace(/\/$/, "");

function authHeaders(token, extra = {}) {
  const headers = { ...extra };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

async function parseResponse(res) {
  const contentType = res.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    const data = await res.json();
    if (!res.ok) {
      const err = new Error(data.error || `HTTP ${res.status}`);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }
  if (!res.ok) {
    const text = await res.text();
    const err = new Error(text || `HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res;
}

export async function login(apiKey) {
  const res = await fetch(`${API_URL}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: apiKey }),
  });
  return parseResponse(res);
}

export async function getMe(token) {
  const res = await fetch(`${API_URL}/api/auth/me`, {
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export async function fetchEquipos(token) {
  const res = await fetch(`${API_URL}/api/equipos`, {
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export async function fetchReportes(token, params = {}) {
  const qs = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      qs.set(key, value);
    }
  });
  const res = await fetch(`${API_URL}/api/reportes?${qs}`, {
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export function downloadUrl(path) {
  return `${API_URL}${path}`;
}

export async function downloadWithAuth(token, path, filenameHint) {
  const res = await fetch(`${API_URL}${path}`, {
    headers: authHeaders(token),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `HTTP ${res.status}`);
  }
  const blob = await res.blob();
  const disposition = res.headers.get("content-disposition") || "";
  const match = disposition.match(/filename=\"?([^\";]+)\"?/i);
  const filename = match ? match[1] : filenameHint || "download";
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export async function generarPdf(token, id) {
  const res = await fetch(`${API_URL}/api/reportes/${id}/generar-pdf`, {
    method: "POST",
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export async function uploadPdf(token, id, file) {
  const form = new FormData();
  form.append("pdf", file);
  const res = await fetch(`${API_URL}/api/reportes/${id}/pdf`, {
    method: "POST",
    headers: authHeaders(token),
    body: form,
  });
  return parseResponse(res);
}

export async function fetchUsuarios(token) {
  const res = await fetch(`${API_URL}/api/usuarios`, {
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export async function createUsuario(token, body) {
  const res = await fetch(`${API_URL}/api/usuarios`, {
    method: "POST",
    headers: authHeaders(token, { "Content-Type": "application/json" }),
    body: JSON.stringify(body),
  });
  return parseResponse(res);
}

export async function patchUsuario(token, id, body) {
  const res = await fetch(`${API_URL}/api/usuarios/${id}`, {
    method: "PATCH",
    headers: authHeaders(token, { "Content-Type": "application/json" }),
    body: JSON.stringify(body),
  });
  return parseResponse(res);
}

export async function deleteUsuario(token, id) {
  const res = await fetch(`${API_URL}/api/usuarios/${id}`, {
    method: "DELETE",
    headers: authHeaders(token),
  });
  if (res.status === 204) return null;
  return parseResponse(res);
}

export async function regenerarKey(token, id) {
  const res = await fetch(`${API_URL}/api/usuarios/${id}/regenerar-key`, {
    method: "POST",
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export async function fetchPrompt(token) {
  const res = await fetch(`${API_URL}/api/prompts/reporte_ejecutivo`, {
    headers: authHeaders(token),
  });
  return parseResponse(res);
}

export async function savePrompt(token, contenido) {
  const res = await fetch(`${API_URL}/api/prompts/reporte_ejecutivo`, {
    method: "PUT",
    headers: authHeaders(token, { "Content-Type": "application/json" }),
    body: JSON.stringify({ contenido }),
  });
  return parseResponse(res);
}
