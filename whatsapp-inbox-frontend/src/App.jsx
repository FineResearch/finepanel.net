import { useEffect, useMemo, useRef, useState } from "react";
import {
  fetchConversations,
  fetchConversationDetail,
  resolveConversation,
  reopenConversation,
  sendTemplate,
  sendText
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
    conversation.id,
    conversation.last_inbound_at || "",
    conversation.last_message_at || "",
    conversation.has_unread_messages ? "1" : "0"
  ].join("|");
}

export default function App() {
  const [filters, setFilters] = useState({
    status: "",
    project_code: ""
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
      const items = data?.conversations || [];

      const nextFingerprintMap = new Map(
        items.map((conversation) => [
          conversation.id,
          buildConversationFingerprint(conversation)
        ])
      );

      if (pollingStartedRef.current) {
        let shouldPlaySound = false;

        for (const conversation of items) {
          const previousFingerprint = knownConversationFingerprintsRef.current.get(conversation.id);
          const currentFingerprint = buildConversationFingerprint(conversation);

          if (!previousFingerprint) {
            shouldPlaySound = true;
            break;
          }

          if (
            previousFingerprint !== currentFingerprint &&
            conversation.last_inbound_at
          ) {
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

      const stillExists = items.some((c) => c.id === selectedConversationId);

      if (!selectedConversationId && items.length > 0) {
        setSelectedConversationId(items[0].id);
      } else if (selectedConversationId && !stillExists) {
        setSelectedConversationId(items[0]?.id || null);
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
      setSelectedConversation(data?.conversation || null);
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

  useEffect(() => {
    loadConversations(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    loadConversations(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters.status, filters.project_code]);

  useEffect(() => {
    loadConversationDetail(selectedConversationId);
  }, [selectedConversationId]);

  useEffect(() => {
    const intervalId = window.setInterval(async () => {
      await loadConversations(true, { silent: true });

      if (selectedConversationId) {
        await loadConversationDetail(selectedConversationId, { silent: true });
      }
    }, 5000);

    return () => {
      window.clearInterval(intervalId);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedConversationId, filters.status, filters.project_code]);

  async function refreshAll(keepCurrentMessage = true) {
    await loadConversations(true);
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
    return conversations.find((c) => c.id === selectedConversationId) || null;
  }, [conversations, selectedConversationId]);

  return (
    <div className="app-shell">
      <header className="app-header">
        <div>
          <h1>WhatsApp Inbox</h1>
          <p>Gestión interna de conversaciones con panelistas</p>
        </div>
      </header>

      <div className="app-body">
        <aside className="sidebar">
          <FiltersBar filters={filters} onChange={setFilters} />

          {listError && <div className="error-box">{listError}</div>}

          <ConversationList
            conversations={conversations}
            selectedConversationId={selectedConversationId}
            onSelectConversation={setSelectedConversationId}
            loading={loadingList}
          />
        </aside>

        <main className="main-panel">
          {globalMessage && <div className="success-box">{globalMessage}</div>}
          {detailError && <div className="error-box">{detailError}</div>}

          <ConversationDetail
            conversation={selectedConversation}
            conversationSummary={selectedConversationSummary}
            loading={loadingDetail}
            actionLoading={actionLoading}
            onResolve={handleResolve}
            onReopen={handleReopen}
            onSendTemplate={handleSendTemplate}
            onSendText={handleSendText}
          />
        </main>
      </div>
    </div>
  );
}
