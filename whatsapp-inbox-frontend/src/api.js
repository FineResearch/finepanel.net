const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "";
const ENV_INTERNAL_USER_EMAIL = import.meta.env.VITE_INTERNAL_USER_EMAIL || "";

function currentInternalUserEmail() {
  const fromQuery = new URLSearchParams(window.location.search).get("internal_user_email");
  return fromQuery || ENV_INTERNAL_USER_EMAIL || "";
}

function buildHeaders(extraHeaders = {}) {
  const headers = {
    "Content-Type": "application/json",
    ...extraHeaders
  };

  const internalUserEmail = currentInternalUserEmail();

  if (internalUserEmail) {
    headers["X-Internal-User-Email"] = internalUserEmail;
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

  const queryString = params.toString();
  const path = queryString
    ? `/internal/whatsapp/conversations?${queryString}`
    : `/internal/whatsapp/conversations`;

  return request(path, { method: "GET" });
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

export async function sendText(id, messageBody) {
  return request(`/internal/whatsapp/conversations/${id}/send_text`, {
    method: "POST",
    body: JSON.stringify({
      body: messageBody
    })
  });
}
