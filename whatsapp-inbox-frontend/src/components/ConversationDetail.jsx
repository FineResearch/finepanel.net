import { useMemo, useState } from "react";

function ContextItem({ label, value, isLink = false }) {
  if (!value) return null;

  return (
    <div className="context-item">
      <span className="context-label">{label}:</span>{" "}
      {isLink ? (
        <a href={value} target="_blank" rel="noreferrer" className="context-link">
          {value}
        </a>
      ) : (
        <span className="context-value">{value}</span>
      )}
    </div>
  );
}

function ConversationContextCard({ context }) {
  if (!context || Object.keys(context).length === 0) return null;

  return (
    <div className="initial-contact-card">
      <h3>Contexto de la conversación</h3>

      <div className="initial-contact-meta">
        {context.project_code && (
          <span>
            Project: <strong>{context.project_code}</strong>
          </span>
        )}
        {context.panelist_id && (
          <span>
            Panelist: <strong>{context.panelist_id}</strong>
          </span>
        )}
      </div>

      <div className="context-grid">
        <ContextItem label="Teléfono" value={context.whatsapp_number} />
        <ContextItem label="País" value={context.panelist_country} />
        <ContextItem label="Enviado" value={context.outbound_sent_at} />
        <ContextItem label="Asunto" value={context.survey_subject} />
        <ContextItem label="Duración" value={context.duration} />
        <ContextItem label="Incentivo" value={context.incentive} />
        <ContextItem label="Sent by" value={context.sent_by} />
        <ContextItem label="Sample number" value={context.sample_number} />
        <ContextItem label="Nombre" value={context.panelist_first_name} />
        <ContextItem label="Apellido" value={context.panelist_last_name} />
        <ContextItem label="Main survey link" value={context.main_survey_link} isLink />
      </div>
    </div>
  );
}

function MessageBubble({ message }) {
  const direction = message.direction || "unknown";
  const isOutbound = direction === "outbound";

  return (
    <div className={`message-row ${isOutbound ? "outbound" : "inbound"}`}>
      <div className={`message-bubble ${isOutbound ? "outbound" : "inbound"}`}>
        <div className="message-direction">
          {isOutbound ? "Outbound" : "Inbound"}
        </div>

        {message.template_name && (
          <div className="message-template">
            Template: {message.template_name}
          </div>
        )}

        <div className="message-body">
          {message.message_body || <span className="muted-text">(sin texto)</span>}
        </div>

        {message.internal_user_id && (
          <div className="message-meta">
            Internal user: {message.internal_user_id}
          </div>
        )}
      </div>
    </div>
  );
}

function InitialContactCard({ initialContact }) {
  if (!initialContact) return null;

  return (
    <div className="initial-contact-card">
      <h3>Contacto inicial</h3>

      <div className="initial-contact-meta">
        {initialContact.project_code && (
          <span>
            Project: <strong>{initialContact.project_code}</strong>
          </span>
        )}
        {initialContact.study_title && (
          <span>
            Estudio: <strong>{initialContact.study_title}</strong>
          </span>
        )}
        {initialContact.template_name && (
          <span>
            Template: <strong>{initialContact.template_name}</strong>
          </span>
        )}
        {initialContact.sent_at && (
          <span>
            Enviado: <strong>{initialContact.sent_at}</strong>
          </span>
        )}
      </div>

      {initialContact.message_body && (
        <div className="initial-contact-body">
          {initialContact.message_body}
        </div>
      )}

      {initialContact.extra_info && (
        <div className="initial-contact-extra">
          {initialContact.extra_info}
        </div>
      )}
    </div>
  );
}

export default function ConversationDetail({
  conversation,
  conversationSummary,
  loading,
  actionLoading,
  onResolve,
  onReopen,
  onSendTemplate,
  onSendText
}) {
  const [templateName, setTemplateName] = useState("");
  const [messageBody, setMessageBody] = useState("");

  const allowedActions = useMemo(() => {
    return conversation?.allowed_actions || conversationSummary?.allowed_actions || {};
  }, [conversation, conversationSummary]);

  const allowedTemplates = allowedActions.allowed_templates || [];
  const canSendFreeText = allowedActions.send_free_text === true;
  const canSendTemplate = allowedActions.send_template === true;

  if (loading) {
    return <div className="panel-placeholder">Cargando detalle...</div>;
  }

  if (!conversation) {
    return <div className="panel-placeholder">Selecciona una conversación</div>;
  }

  async function handleTemplateSubmit(e) {
    e.preventDefault();
    if (!templateName.trim()) return;
    await onSendTemplate(templateName.trim());
    setTemplateName("");
  }

  async function handleTextSubmit(e) {
    e.preventDefault();
    if (!messageBody.trim()) return;
    await onSendText(messageBody.trim());
    setMessageBody("");
  }

  return (
    <div className="detail-shell">
      <div className="detail-header">
        <div>
          <h2>Conversación #{conversation.id}</h2>
          <div className="detail-meta">
            <span>
              Estado: <strong>{conversation.status || "-"}</strong>
            </span>
            <span>
              Panelist: <strong>{conversation.panelist_id || "-"}</strong>
            </span>
            <span>
              Project: <strong>{conversation.project_code || "-"}</strong>
            </span>
          </div>
        </div>

        <div className="header-actions">
          {conversation.status === "resolved" ? (
            <button
              className="secondary-button"
              onClick={onReopen}
              disabled={actionLoading}
            >
              {actionLoading ? "Procesando..." : "Reopen"}
            </button>
          ) : (
            <button
              className="primary-button"
              onClick={onResolve}
              disabled={actionLoading}
            >
              {actionLoading ? "Procesando..." : "Resolve"}
            </button>
          )}
        </div>
      </div>

      <ConversationContextCard context={conversation.conversation_context} />

      <InitialContactCard initialContact={conversation.initial_contact} />

      <div className="messages-panel">
        {(conversation.messages || []).length === 0 ? (
          <div className="panel-placeholder">No hay mensajes en esta conversación</div>
        ) : (
          (conversation.messages || []).map((message, index) => (
            <MessageBubble
              key={message.id || `${message.direction}-${index}-${message.message_body || ""}`}
              message={message}
            />
          ))
        )}
      </div>

      <div className="composer-grid">
        <form className="composer-box" onSubmit={handleTemplateSubmit}>
          <h3>Enviar template</h3>

          <select
            value={templateName}
            onChange={(e) => setTemplateName(e.target.value)}
            disabled={actionLoading || !canSendTemplate}
          >
            <option value="">Seleccionar template</option>
            {allowedTemplates.map((template) => (
              <option key={template} value={template}>
                {template}
              </option>
            ))}
          </select>

          <button
            className="primary-button"
            type="submit"
            disabled={actionLoading || !canSendTemplate || !templateName}
          >
            Enviar template
          </button>

          {!canSendTemplate && (
            <p className="muted-text">
              El backend indica que no se pueden enviar templates en esta conversación.
            </p>
          )}
        </form>

        <form className="composer-box" onSubmit={handleTextSubmit}>
          <h3>Enviar texto</h3>

          <textarea
            rows="4"
            value={messageBody}
            onChange={(e) => setMessageBody(e.target.value)}
            placeholder="Escribe un mensaje..."
            disabled={actionLoading || !canSendFreeText}
          />

          <button
            className="primary-button"
            type="submit"
            disabled={actionLoading || !canSendFreeText || !messageBody.trim()}
          >
            Enviar texto
          </button>

          {!canSendFreeText && (
            <p className="muted-text">
              Free text no permitido. Usa un template para reabrir o continuar.
            </p>
          )}
        </form>
      </div>
    </div>
  );
}
