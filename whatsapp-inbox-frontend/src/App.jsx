import { useEffect, useMemo, useRef, useState } from "react";
import { sendReminder } from "./api";

import {
  fetchConversations,
  fetchConversationDetail,
  resolveConversation,
  reopenConversation,
  sendTemplate,
  sendText,
  fetchProjectMetrics
} from "./api";

import FiltersBar from "./components/FiltersBar";
import ConversationList from "./components/ConversationList";
import ConversationDetail from "./components/ConversationDetail";

function playNotificationSound() {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;

    const audioContext = new AudioContextClass();
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(880, audioContext.currentTime);

    gainNode.gain.setValueAtTime(0.0001, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.08, audioContext.currentTime + 0.01);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, audioContext.currentTime + 0.22);

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    oscillator.start();
    oscillator.stop(audioContext.currentTime + 0.22);

    oscillator.onended = () => {
      if (audioContext && typeof audioContext.close === "function") {
        audioContext.close();
      }
    };
  } catch (_error) {
    // no-op
  }
}

function buildConversationFingerprint(conversation) {
  return [
    conversation?.id || "",
    conversation?.last_inbound_at || "",
    conversation?.last_message_at || "",
    conversation?.has_unread_messages ? "1" : "0"
  ].join("|");
}

function normalizeConversationDetail(rawConversation) {
  if (!rawConversation || typeof rawConversation !== "object") return null;

  const context =
    rawConversation.context && typeof rawConversation.context === "object"
      ? rawConversation.context
      : rawConversation.conversation_context &&
        typeof rawConversation.conversation_context === "object"
      ? rawConversation.conversation_context
      : rawConversation.metadata && typeof rawConversation.metadata === "object"
      ? rawConversation.metadata
      : {};

  const messages = Array.isArray(rawConversation.messages)
    ? rawConversation.messages
    : Array.isArray(rawConversation.whatsapp_messages)
    ? rawConversation.whatsapp_messages
    : Array.isArray(rawConversation.conversation_messages)
    ? rawConversation.conversation_messages
    : Array.isArray(rawConversation.message_log)
    ? rawConversation.message_log
    : [];

  const allowedTemplates = Array.isArray(rawConversation.allowed_templates)
    ? rawConversation.allowed_templates
    : Array.isArray(rawConversation.templates)
    ? rawConversation.templates
    : Array.isArray(context.allowed_templates)
    ? context.allowed_templates
    : [];

  return {
    ...rawConversation,
    context,
    messages,
    allowed_templates: allowedTemplates
  };
}

export default function App() {
  const [filters, setFilters] = useState({
    status: "",
    project_code: "",
    last_reply_type: "",
    last_reply_answered: "",
    last_reply_window: "",
    country: "",
    limit: "50"
  });

  const [conversations, setConversations] = useState([]);
  const [selectedConversationId, setSelectedConversationId] = useState(null);
  const [selectedConversation, setSelectedConversation] = useState(null);

  const [loadingList, setLoadingList] = useState(false);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);

  const [listError, setListError] = useState("");
  const [detailError, setDetailError] = useState("");
  const [globalMessage, setGlobalMessage] = useState("");
  const [metrics, setMetrics] = useState({});
  const [summary, setSummary] = useState({});

  const knownConversationFingerprintsRef = useRef(new Map());
  const pollingStartedRef = useRef(false);

  async function loadConversations(preserveSelected = true, options = {}) {
    const { silent = false } = options;

    if (!silent) {
      setLoadingList(true);
      setListError("");
    }

    try {
      const data = await fetchConversations(filters);
      const items = Array.isArray(data?.conversations) ? data.conversations : [];

      const nextFingerprintMap = new Map(
        items.map((conversation) => [
          conversation?.id,
          buildConversationFingerprint(conversation)
        ])
      );

      if (pollingStartedRef.current) {
        let shouldPlaySound = false;

        for (const conversation of items) {
          const previousFingerprint = knownConversationFingerprintsRef.current.get(conversation?.id);
          const currentFingerprint = buildConversationFingerprint(conversation);

          if (!previousFingerprint) {
            shouldPlaySound = true;
            break;
          }

          if (previousFingerprint !== currentFingerprint && conversation?.last_inbound_at) {
            shouldPlaySound = true;
            break;
          }
        }

        if (shouldPlaySound) {
          playNotificationSound();
        }
      }

      knownConversationFingerprintsRef.current = nextFingerprintMap;
      pollingStartedRef.current = true;

      setConversations(items);

      if (!preserveSelected) {
        setSelectedConversationId(items[0]?.id || null);
        return;
      }

      // Solo seleccionar automáticamente si todavía no hay conversación seleccionada.
      // No cambiar automáticamente una conversación ya elegida por el agente.
      if (!selectedConversationId && items.length > 0) {
        setSelectedConversationId(items[0].id);
      }
    } catch (error) {
      if (!silent) {
        setListError(error.message || "No se pudo cargar la lista");
      }
    } finally {
      if (!silent) {
        setLoadingList(false);
      }
    }
  }

  async function loadConversationDetail(id, options = {}) {
    const { silent = false } = options;

    if (!id) {
      setSelectedConversation(null);
      return;
    }

    if (!silent) {
      setLoadingDetail(true);
      setDetailError("");
    }

    try {
      const data = await fetchConversationDetail(id);

      const rawConversation =
        data?.conversation && typeof data.conversation === "object"
          ? data.conversation
          : data && typeof data === "object"
          ? data
          : null;

      setSelectedConversation(normalizeConversationDetail(rawConversation));
    } catch (error) {
      if (!silent) {
        setDetailError(error.message || "No se pudo cargar el detalle");
      }
    } finally {
      if (!silent) {
        setLoadingDetail(false);
      }
    }
  }

  async function loadProjectMetrics(options = {}) {
    const { silent = false } = options;

    try {
      const data = await fetchProjectMetrics();
      if (data?.success) {
        setMetrics(data?.metrics && typeof data.metrics === "object" ? data.metrics : {});
        setSummary(data?.summary && typeof data.summary === "object" ? data.summary : {});
      }
    } catch (_error) {
      if (!silent) {
        // no-op
      }
    }
  }

  useEffect(() => {
    loadConversations(false);
    loadProjectMetrics();

    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    loadConversations(true);
    loadProjectMetrics({ silent: true });

    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    filters.status,
    filters.project_code,
    filters.last_reply_type,
    filters.last_reply_answered,
    filters.last_reply_window,
    filters.country,
    filters.limit
  ]);

  useEffect(() => {
    loadConversationDetail(selectedConversationId);
  }, [selectedConversationId]);

  async function refreshAll(keepCurrentMessage = true) {
    await loadConversations(true);
    await loadProjectMetrics({ silent: true });

    if (selectedConversationId) {
      await loadConversationDetail(selectedConversationId);
    }

    if (!keepCurrentMessage) {
      setGlobalMessage("");
    }
  }

  async function handleResolve() {
    if (!selectedConversationId) return;

    setActionLoading(true);
    setGlobalMessage("");
    try {
      await resolveConversation(selectedConversationId);
      setGlobalMessage("Conversación resuelta");
      await refreshAll();
    } catch (error) {
      setDetailError(error.message || "No se pudo resolver");
    } finally {
      setActionLoading(false);
    }
  }

  async function handleSendReminder() {
    if (!selectedConversationId) return;

    setActionLoading(true);
    setGlobalMessage("");
    setDetailError("");

    try {
      await sendReminder(selectedConversationId);
      setGlobalMessage("Reminder enviado");
      await refreshAll();
    } catch (error) {
      setDetailError(error.message || "No se pudo enviar el reminder");
    } finally {
      setActionLoading(false);
    }
  }

  async function handleReopen() {
    if (!selectedConversationId) return;

    setActionLoading(true);
    setGlobalMessage("");
    try {
      await reopenConversation(selectedConversationId);
      setGlobalMessage("Conversación reabierta");
      await refreshAll();
    } catch (error) {
      setDetailError(error.message || "No se pudo reabrir");
    } finally {
      setActionLoading(false);
    }
  }

  async function handleSendTemplate(templateName) {
    if (!selectedConversationId) return;

    setActionLoading(true);
    setGlobalMessage("");
    setDetailError("");

    try {
      await sendTemplate(selectedConversationId, templateName);
      setGlobalMessage("Template enviado");
      await refreshAll();
    } catch (error) {
      setDetailError(error.message || "No se pudo enviar el template");
    } finally {
      setActionLoading(false);
    }
  }

  async function handleSendText(messageBody) {
    if (!selectedConversationId) return;

    setActionLoading(true);
    setGlobalMessage("");
    setDetailError("");

    try {
      await sendText(selectedConversationId, messageBody);
      setGlobalMessage("Mensaje enviado");
      await refreshAll();
    } catch (error) {
      setDetailError(error.message || "No se pudo enviar el mensaje");
    } finally {
      setActionLoading(false);
    }
  }

  const selectedConversationSummary = useMemo(() => {
    const safeConversations = Array.isArray(conversations) ? conversations : [];
    return safeConversations.find((c) => c?.id === selectedConversationId) || null;
  }, [conversations, selectedConversationId]);

  const filteredProjectCode = useMemo(() => {
    return String(filters.project_code || "").trim();
  }, [filters.project_code]);

  const effectiveMetrics = useMemo(() => {
    if (filteredProjectCode) {
      const projectMetrics =
        metrics?.[filteredProjectCode] && typeof metrics[filteredProjectCode] === "object"
          ? metrics[filteredProjectCode]
          : {};

      return projectMetrics;
    }

    return summary && typeof summary === "object" ? summary : {};
  }, [metrics, summary, filteredProjectCode]);

  return (
    <div className="app-shell">
      <header className="app-header">
        <div>
          <h1>WhatsApp Inbox</h1>
          <p>Gestión interna de conversaciones con panelistas</p>
        </div>

        <button
          type="button"
          onClick={() => refreshAll()}
          disabled={loadingList || loadingDetail || actionLoading}
        >
          {loadingList || loadingDetail ? "Actualizando..." : "Actualizar"}
        </button>
      </header>

      {globalMessage && <div className="success-box">{globalMessage}</div>}
      {detailError && <div className="error-box">{detailError}</div>}

      <div
        className="app-body"
        style={{
          display: "grid",
          gridTemplateColumns: "360px minmax(0, 1fr)",
          gap: 16,
          alignItems: "start"
        }}
      >
        <aside
          className="sidebar"
          style={{
            minWidth: 0,
            display: "flex",
            flexDirection: "column",
            gap: 12
          }}
        >
          <FiltersBar filters={filters} onChange={setFilters} />
          {listError && <div className="error-box">{listError}</div>}

          <ConversationList
            conversations={Array.isArray(conversations) ? conversations : []}
            selectedConversationId={selectedConversationId}
            onSelectConversation={setSelectedConversationId}
            loading={loadingList}
            showSelectionSummary={false}
          />
        </aside>

        <section style={{ minWidth: 0 }}>
          <ConversationDetail
            conversation={selectedConversation}
            conversationSummary={selectedConversationSummary}
            conversations={conversations}
            loading={loadingDetail}
            actionLoading={actionLoading}
            onResolve={handleResolve}
            onReopen={handleReopen}
            onSendTemplate={handleSendTemplate}
            onSendText={handleSendText}
            metrics={effectiveMetrics}
            metricsScopeLabel=""
            onSendReminder={handleSendReminder}
          />
        </section>
      </div>
    </div>
  );
}
