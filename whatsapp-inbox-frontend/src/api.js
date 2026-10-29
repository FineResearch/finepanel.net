const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "";
// Login comun de las herramientas internas (pagina /internal): el token vive en
// la misma clave de localStorage que usa el Wizard.
const AUTH_TOKEN_KEY = "fpSetupAuthToken";
const LOGIN_PATH = "/internal";

function getAuthToken() {
  try {
    return localStorage.getItem(AUTH_TOKEN_KEY) || "";
  } catch (error) {
    return "";
  }
}

function redirectToLogin() {
  try {
    localStorage.removeItem(AUTH_TOKEN_KEY);
  } catch (error) {
    // sin localStorage no hay nada que limpiar
  }

  const next = encodeURIComponent(window.location.pathname);
  window.location.replace(`${LOGIN_PATH}?next=${next}`);
}

function buildHeaders(extraHeaders = {}) {
  const headers = {
    "Content-Type": "application/json",
    ...extraHeaders
  };

  const token = getAuthToken();

  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  return headers;
}


async function parseJsonSafe(response) {
  const text = await response.text();

  try {
    return text ? JSON.parse(text) : {};
  } catch (error) {
    throw new Error(`Respuesta JSON inválida (${response.status}): ${text}`);
  }
}

async function request(path, options = {}) {
  const url = `${API_BASE_URL}${path}`;

  const response = await fetch(url, {
    credentials: "include",
    ...options,
    headers: buildHeaders(options.headers || {})
  });

  if (response.status === 401) {
    redirectToLogin();
    throw new Error("Sesión vencida. Redirigiendo al login...");
  }

  const data = await parseJsonSafe(response);

  if (!response.ok) {
    const message =
      data?.error ||
      data?.message ||
      `Error HTTP ${response.status} al llamar ${path}`;
    throw new Error(message);
  }

  if (data?.success === false) {
    throw new Error(data?.error || data?.message || "La operación falló");
  }

  return data;
}

export async function fetchConversations(filters = {}) {
  const params = new URLSearchParams();

  if (filters.status) params.append("status", filters.status);
  if (filters.project_code) params.append("project_code", filters.project_code);
  if (filters.last_reply_type) params.append("last_reply_type", filters.last_reply_type);
  if (filters.last_reply_answered) params.append("last_reply_answered", filters.last_reply_answered);
  if (filters.last_reply_window) params.append("last_reply_window", filters.last_reply_window);
  if (filters.limit) params.append("limit", filters.limit);
  if (filters.country) params.append("country", filters.country);
  if (filters.panelist_id) params.append("panelist_id", filters.panelist_id);


  const queryString = params.toString();
  const path = queryString
    ? `/internal/whatsapp/conversations?${queryString}`
    : `/internal/whatsapp/conversations`;

  return request(path, { method: "GET" });
}

export async function exportProjectInvitesAsync(filters = {}, email) {
  return request("/internal/whatsapp/conversations/export_project_invites_async", {
    method: "POST",
    body: JSON.stringify({
      email,
      project_code: filters.project_code
    })
  });
}


export async function fetchConversationDetail(id) {
  return request(`/internal/whatsapp/conversations/${id}`, {
    method: "GET"
  });
}

export async function resolveConversation(id) {
  return request(`/internal/whatsapp/conversations/${id}/resolve`, {
    method: "POST",
    body: JSON.stringify({})
  });
}

export async function reopenConversation(id) {
  return request(`/internal/whatsapp/conversations/${id}/reopen`, {
    method: "POST",
    body: JSON.stringify({})
  });
}

export async function sendTemplate(id, templateName) {
  return request(`/internal/whatsapp/conversations/${id}/send_template`, {
    method: "POST",
    body: JSON.stringify({
      template_name: templateName
    })
  });
}

export async function sendReminder(id) {
  return request(`/internal/whatsapp/conversations/${id}/send_reminder`, {
    method: "POST",
    body: JSON.stringify({})
  });
}


export async function sendText(id, messageBody) {
  return request(`/internal/whatsapp/conversations/${id}/send_text`, {
    method: "POST",
    body: JSON.stringify({
      body: messageBody
    })
  });
}

export async function fetchProjectMetrics() {
  return request("/internal/whatsapp/conversations/project_metrics", {
    method: "GET"
  });
}


export async function exportConversations(filters = {}) {
  const params = new URLSearchParams();

  Object.entries(filters).forEach(([k, v]) => {
    if (v) params.append(k, v);
  });

  const query = params.toString();
  const url = query
    ? `${API_BASE_URL}/internal/whatsapp/conversations/export?${query}`
    : `${API_BASE_URL}/internal/whatsapp/conversations/export`;

  const response = await fetch(url, { headers: buildHeaders() });

  if (response.status === 401) {
    redirectToLogin();
    throw new Error("Sesión vencida. Redirigiendo al login...");
  }

  if (!response.ok) {
    throw new Error(`Error HTTP ${response.status} al exportar conversaciones`);
  }

  const blob = await response.blob();
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "conversaciones.csv";
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(link.href);
}

export async function exportConversationsAsync(filters = {}, email) {
  const body = {
    ...filters,
    email
  };

  return request("/internal/whatsapp/conversations/export_async", {
    method: "POST",
    body: JSON.stringify(body)
  });
}

