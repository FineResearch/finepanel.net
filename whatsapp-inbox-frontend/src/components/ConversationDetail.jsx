import { useEffect, useMemo, useRef, useState } from "react";

function formatDateTime(value) {
  if (!value) return "-";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);

  return date.toLocaleString();
}

function formatMessageType(message) {
  if (!message) return "-";

  return (
    message.message_type ||
    message.kind ||
    message.type ||
    message.source ||
    message.event_type ||
    "-"
  );
}

function getMessageBody(message) {
  if (!message) return "";

  const directBody =
    message.message_body ??
    message.body ??
    message.text ??
    message.content ??
    message.preview ??
    message.message ??
    "";

  if (directBody !== null && directBody !== undefined && directBody !== "") {
    return String(directBody);
  }

  if (message.payload && typeof message.payload === "object") {
    const payloadBody =
      message.payload.body ||
      message.payload.text ||
      message.payload.message ||
      message.payload.content ||
      "";

    return payloadBody ? String(payloadBody) : "";
  }

  if (message.payload_json && typeof message.payload_json === "object") {
    const payloadJsonBody =
      message.payload_json.body ||
      message.payload_json.text ||
      message.payload_json.message ||
      message.payload_json.content ||
      "";

    return payloadJsonBody ? String(payloadJsonBody) : "";
  }

  return "";
}

function getDirectionLabel(direction) {
  if (direction === "inbound") return "Entrante";
  if (direction === "outbound") return "Saliente";
  return direction || "-";
}

function pickFirstValue(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null && value !== "") {
      return value;
    }
  }
  return "";
}

function pickMetric(source, ...keys) {
  if (!source || typeof source !== "object") return 0;

  for (const key of keys) {
    const value = source[key];
    if (value !== undefined && value !== null && value !== "") {
      return value;
    }
  }

  return 0;
}

function MetricsBox({ metrics, metricsScopeLabel }) {
  const safeMetrics = metrics && typeof metrics === "object" ? metrics : {};

  const totalSent = pickMetric(safeMetrics, "total_sent_messages", "sent_messages", "sent", "total_sent") || 0;
  const totalFailed = pickMetric(safeMetrics, "total_failed_messages", "failed_messages", "failed", "total_failed") || 0;
  const totalInvalid = pickMetric(safeMetrics, "total_invalid_messages", "invalid_messages", "invalid", "total_invalid") || 0;
  const totalResponded = pickMetric(safeMetrics, "total_responded_panelists", "responded_panelists", "responded") || 0;
  const totalContacted = pickMetric(safeMetrics, "total_contacted_panelists", "contacted_panelists", "total_contacted") || 0;
  const totalAgent = pickMetric(safeMetrics, "total_agent_interactions", "agent_interactions", "total_agent_intervened") || 0;

  const sent24h = pickMetric(safeMetrics, "sent_last_24h", "sent_messages_last_24h", "total_sent_messages_last_24h", "last_24h_sent") || 0;
  const responded24h = pickMetric(safeMetrics, "responded_last_24h", "responded_panelists_last_24h", "total_responded_panelists_last_24h", "last_24h_responded") || 0;
  const unique24h = pickMetric(safeMetrics, "unique_whatsapp_numbers_last_24h", "unique_recipients_last_24h", "last_24h_unique_recipients") || 0;

  const dailyLimit = pickMetric(safeMetrics, "daily_limit", "limit_24h") || 2000;
  const remainingCapacity = pickMetric(safeMetrics, "remaining_capacity", "available_capacity") || 0;

  return (
    <div style={{ padding: "12px 14px", border: "1px solid #dbe7f3", borderRadius: 12, background: "#eef6ff", marginBottom: 12 }}>
      <div style={{ fontWeight: "bold", marginBottom: 8 }}>Métricas de envíos</div>

      {metricsScopeLabel ? (
        <div style={{ fontSize: 13, color: "#475569", marginBottom: 10 }}>
          {metricsScopeLabel}
        </div>
      ) : null}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 8 }}>
        <div><strong>Sent 24h:</strong> {sent24h}</div>
        <div><strong>Responded 24h:</strong> {responded24h}</div>
        <div><strong>Unique 24h:</strong> {unique24h}</div>
        <div><strong>Remaining:</strong> {remainingCapacity}</div>
        <div><strong>Daily limit:</strong> {dailyLimit}</div>
        <div><strong>Histórico sent:</strong> {totalSent}</div>
        <div><strong>Histórico responded:</strong> {totalResponded}</div>
        <div><strong>Contacted:</strong> {totalContacted}</div>
        <div><strong>Agent interactions:</strong> {totalAgent}</div>
        <div><strong>Failed:</strong> {totalFailed}</div>
        <div><strong>Invalid:</strong> {totalInvalid}</div>
      </div>
    </div>
  );
}

function SelectionSummaryBox({ conversations }) {
  const safeConversations = Array.isArray(conversations) ? conversations : [];

  const summary = useMemo(() => {
    return safeConversations.reduce(
      (acc, conversation) => {
        const replyType = conversation?.last_inbound_reply_type;

        if (replyType === "one") acc.one += 1;
        else if (replyType === "two") acc.two += 1;
        else if (replyType === "other") acc.other += 1;

        if (conversation?.requires_human_follow_up && conversation?.status === "open") {
          acc.pending += 1;
        }

        if (conversation?.has_unread_messages) {
          acc.unread += 1;
        }

        acc.total += 1;
        return acc;
      },
      { total: 0, one: 0, two: 0, other: 0, pending: 0, unread: 0 }
    );
  }, [safeConversations]);

  return (
    <div style={{ padding: "12px 14px", border: "1px solid #dbe7f3", borderRadius: 12, background: "#f8fafc", marginBottom: 12 }}>
      <div style={{ fontWeight: "bold", marginBottom: 8 }}>Resumen de selección</div>
      <div>Total conversaciones: <strong>{summary.total}</strong></div>
      <div>Pendientes humanas: <strong>{summary.pending}</strong></div>
      <div>No leídas: <strong>{summary.unread}</strong></div>
      <div>Última respuesta = 1: <strong>{summary.one}</strong></div>
      <div>Última respuesta = 2: <strong>{summary.two}</strong></div>
      <div>Otras: <strong>{summary.other}</strong></div>
    </div>
  );
}

export default function ConversationDetail({
  conversation,
  conversationSummary,
  conversations,
  loading,
  actionLoading,
  onResolve,
  onReopen,
  onSendTemplate,
  onSendText,
  onSendReminder,
  metrics,
  metricsScopeLabel
}) {
  const [textBody, setTextBody] = useState("");
  const [showMetrics, setShowMetrics] = useState(false);
  const [showSelectionSummary, setShowSelectionSummary] = useState(false);
  const messagesEndRef = useRef(null);

  const safeConversation = conversation && typeof conversation === "object" ? conversation : null;
  const safeSummary = conversationSummary && typeof conversationSummary === "object" ? conversationSummary : null;
  const safeConversations = Array.isArray(conversations) ? conversations : [];

  const context = useMemo(() => {
    if (!safeConversation) return {};

    return safeConversation.context && typeof safeConversation.context === "object"
      ? safeConversation.context
      : safeConversation.conversation_context &&
        typeof safeConversation.conversation_context === "object"
      ? safeConversation.conversation_context
      : {};
  }, [safeConversation]);

  const messages = useMemo(() => {
    const rawMessages =
      safeConversation?.messages ||
      safeConversation?.conversation_messages ||
      safeConversation?.whatsapp_messages ||
      safeConversation?.message_log ||
      [];

    return Array.isArray(rawMessages) ? rawMessages : [];
  }, [safeConversation]);

  const allowedTemplates = useMemo(() => {
    const rawTemplates =
      safeConversation?.allowed_templates ||
      safeConversation?.templates ||
      context?.allowed_templates ||
      [];

    return Array.isArray(rawTemplates) ? rawTemplates : [];
  }, [safeConversation, context]);

  const sortedMessages = useMemo(() => {
    return messages.slice().sort((a, b) => {
      const aDate = new Date(a?.created_at || a?.sent_at || a?.timestamp || a?.updated_at || 0).getTime();
      const bDate = new Date(b?.created_at || b?.sent_at || b?.timestamp || b?.updated_at || 0).getTime();

      return aDate - bDate;
    });
  }, [messages]);

  const status = pickFirstValue(safeConversation?.status, safeSummary?.status, "-");

  const windowStatus = pickFirstValue(
    safeConversation?.conversation_window_status,
    context.conversation_window_status,
    safeConversation?.window_status,
    "closed"
  );

  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: "auto", block: "end" });
    }
  }, [sortedMessages.length, safeConversation?.id]);

  function scrollToBottom() {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth", block: "end" });
    }
  }

  function handleSubmitText(event) {
    event.preventDefault();

    const trimmed = textBody.trim();
    if (!trimmed || actionLoading || windowStatus !== "open") return;

    onSendText(trimmed);
    setTextBody("");
  }

  if (loading) {
    return <div className="panel-card">Cargando detalle...</div>;
  }

  if (!safeConversation) {
    return (
      <div className="panel-card">
        <div style={{ fontWeight: "bold", marginBottom: 8 }}>
          Sin conversación seleccionada
        </div>
        <div>Selecciona una conversación para ver el detalle.</div>
      </div>
    );
  }

  const panelistId = pickFirstValue(safeConversation.panelist_id, context.panelist_id, safeSummary?.panelist_id, "-");
  const projectCode = pickFirstValue(safeConversation.project_code, context.project_code, safeSummary?.project_code, "-");
  const panelistFirstName = pickFirstValue(safeConversation.panelist_first_name, context.panelist_first_name, context.first_name, safeConversation.first_name, "-");
  const panelistLastName = pickFirstValue(safeConversation.panelist_last_name, context.panelist_last_name, context.last_name, safeConversation.last_name, "-");
  const panelistCountry = pickFirstValue(safeConversation.panelist_country, context.panelist_country, context.country, safeSummary?.panelist_country, "-");
  const panelistEmail = pickFirstValue(safeConversation.panelist_email, context.panelist_email, context.email, safeConversation.email, "-");
  const whatsappNumber = pickFirstValue(safeConversation.whatsapp_number, context.whatsapp_number, context.panelist_whatsapp_number, context.from_phone_number, "-");
  const templateName = pickFirstValue(safeConversation.template_name, context.template_name, safeConversation.last_template_name, "-");
  const templateLanguage = pickFirstValue(safeConversation.template_language, context.template_language, safeConversation.language, "-");
  const surveySubject = pickFirstValue(safeConversation.survey_subject, context.survey_subject, context.subject, "-");
  const duration = pickFirstValue(safeConversation.duration, context.duration, "-");
  const incentive = pickFirstValue(safeConversation.incentive, context.incentive, "-");
  const sentBy = pickFirstValue(safeConversation.sent_by, context.sent_by, context.support_email, "-");
  const mainSurveyLink = pickFirstValue(safeConversation.main_survey_link, context.main_survey_link, context.survey_link, "");
  const resolvedAt = pickFirstValue(safeConversation.resolved_at, null);

  return (
    <div className="conversation-detail">
      <div className="panel-card" style={{ background: "#fffef2", border: "1px solid #f3e8a6", marginBottom: 12 }}>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "flex-start", flexWrap: "wrap", marginBottom: 12 }}>
          <div>
            <div style={{ fontSize: 22, fontWeight: "bold", marginBottom: 4 }}>
              Conversación #{safeConversation.id}
            </div>
            <div style={{ color: "#475569" }}>
              Estado: <strong>{status}</strong>
            </div>
          </div>

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button type="button" onClick={() => setShowMetrics((v) => !v)}>
              {showMetrics ? "Ocultar métricas" : "Mostrar métricas"}
            </button>

            <button type="button" onClick={() => setShowSelectionSummary((v) => !v)}>
              {showSelectionSummary ? "Ocultar resumen selección" : "Mostrar resumen selección"}
            </button>

            <button type="button" onClick={onSendReminder} disabled={actionLoading} style={{ background: "#e0f2fe", border: "1px solid #7dd3fc" }}>
              Enviar reminder
            </button>

            {status === "open" ? (
              <button type="button" onClick={onResolve} disabled={actionLoading}>
                {actionLoading ? "Procesando..." : "Resolver"}
              </button>
            ) : (
              <button type="button" onClick={onReopen} disabled={actionLoading}>
                {actionLoading ? "Procesando..." : "Reabrir"}
              </button>
            )}
          </div>
        </div>

        {showMetrics ? <MetricsBox metrics={metrics} metricsScopeLabel={metricsScopeLabel} /> : null}
        {showSelectionSummary ? <SelectionSummaryBox conversations={safeConversations} /> : null}

        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 10, marginBottom: 12 }}>
          <div><strong>Panelist ID:</strong> {panelistId}</div>
          <div><strong>Proyecto:</strong> {projectCode}</div>
          <div><strong>Nombre:</strong> {panelistFirstName}</div>
          <div><strong>Apellido:</strong> {panelistLastName}</div>
          <div><strong>País:</strong> {panelistCountry}</div>
          <div><strong>Email:</strong> {panelistEmail}</div>
          <div><strong>WhatsApp:</strong> {whatsappNumber}</div>
          <div><strong>Window:</strong> {windowStatus}</div>
          <div><strong>Template:</strong> {templateName}</div>
          <div><strong>Idioma:</strong> {templateLanguage}</div>
          <div><strong>Asunto:</strong> {surveySubject}</div>
          <div><strong>Duración:</strong> {duration}</div>
          <div><strong>Incentivo:</strong> {incentive}</div>
          <div><strong>Enviado por:</strong> {sentBy}</div>
          <div><strong>Resuelta en:</strong> {formatDateTime(resolvedAt)}</div>
        </div>

        {mainSurveyLink ? (
          <div style={{ marginBottom: 12 }}>
            <strong>Survey link:</strong>{" "}
            <a href={mainSurveyLink} target="_blank" rel="noreferrer">
              abrir enlace
            </a>
          </div>
        ) : null}

        {allowedTemplates.length > 0 ? (
          <div style={{ marginBottom: 12 }}>
            <div style={{ fontWeight: "bold", marginBottom: 8 }}>
              Templates permitidos
            </div>

            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {allowedTemplates.map((templateNameItem, index) => {
                const value = String(templateNameItem || "").trim();
                if (!value) return null;

                return (
                  <button key={`${value}-${index}`} type="button" onClick={() => onSendTemplate(value)} disabled={actionLoading}>
                    {value}
                  </button>
                );
              })}
            </div>
          </div>
        ) : null}

        <div>
          <div style={{ fontWeight: "bold", marginBottom: 8 }}>
            Enviar mensaje libre
          </div>

          {windowStatus !== "open" ? (
            <div style={{ marginBottom: 10, padding: 8, borderRadius: 8, background: "#fff1f2", border: "1px solid #fecaca", color: "#991b1b", fontSize: 13 }}>
              Free text no permitido (fuera de ventana de 24h)
            </div>
          ) : null}

          <form onSubmit={handleSubmitText}>
            <textarea
              value={textBody}
              onChange={(event) => setTextBody(event.target.value)}
              rows={4}
              placeholder="Escribe un mensaje..."
              style={{ width: "100%", boxSizing: "border-box", padding: 10, borderRadius: 8, border: "1px solid #cbd5e1", resize: "vertical" }}
              disabled={actionLoading || windowStatus !== "open"}
            />

            <div style={{ marginTop: 10, display: "flex", gap: 8, flexWrap: "wrap" }}>
              <button type="submit" disabled={actionLoading || !textBody.trim() || windowStatus !== "open"}>
                {actionLoading ? "Enviando..." : "Enviar mensaje"}
              </button>

              <button type="button" onClick={onSendReminder} disabled={actionLoading} style={{ background: "#e0f2fe", border: "1px solid #7dd3fc" }}>
                Enviar reminder
              </button>
            </div>
          </form>
        </div>
      </div>

      <div className="panel-card">
        <div style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "center", flexWrap: "wrap", marginBottom: 12 }}>
          <div style={{ fontWeight: "bold" }}>
            Mensajes de la conversación #{safeConversation.id} ({sortedMessages.length})
          </div>

          <button type="button" onClick={scrollToBottom} disabled={sortedMessages.length === 0}>
            Ir al último
          </button>
        </div>

        <div style={{ minHeight: 180, maxHeight: "48vh", overflowY: "auto", border: "1px solid #e5e7eb", borderRadius: 10, padding: 12, background: "#f8fafc" }}>
          {sortedMessages.length === 0 ? (
            <div style={{ color: "#64748b" }}>
              No hay mensajes para mostrar.
            </div>
          ) : (
            sortedMessages.map((message, index) => {
              const direction = message?.direction || "";
              const inbound = direction === "inbound";
              const body = getMessageBody(message);

              return (
                <div
                  key={message?.id || `${direction}-${index}`}
                  style={{ marginBottom: 10, padding: 12, borderRadius: 10, background: inbound ? "#ffffff" : "#eaf4ff", border: "1px solid #dbe4ee" }}
                >
                  <div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", marginBottom: 6, fontSize: 13, color: "#475569" }}>
                    <div>
                      <strong>{getDirectionLabel(direction)}</strong>
                      {" · "}
                      {formatMessageType(message)}
                    </div>
                    <div>
                      {formatDateTime(message?.created_at || message?.sent_at || message?.timestamp || message?.updated_at)}
                    </div>
                  </div>

                  <div style={{ whiteSpace: "pre-wrap", color: "#0f172a" }}>
                    {typeof body === "string" && body.length > 0 ? body : <em>(sin contenido)</em>}
                  </div>
                </div>
              );
            })
          )}

          <div ref={messagesEndRef} />
        </div>
      </div>
    </div>
  );
}
EOF
