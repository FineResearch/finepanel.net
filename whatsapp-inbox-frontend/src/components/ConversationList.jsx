import { useMemo } from "react";

function SelectionSummary({ conversations = [] }) {
  const safeConversations = Array.isArray(conversations) ? conversations : [];

  const summary = useMemo(() => {
    return safeConversations.reduce(
      (acc, conversation) => {
        const replyType = conversation?.last_inbound_reply_type;

        if (replyType === "one") {
          acc.one += 1;
        } else if (replyType === "two") {
          acc.two += 1;
        } else if (replyType === "other") {
          acc.other += 1;
        }

        acc.total += 1;
        return acc;
      },
      { total: 0, one: 0, two: 0, other: 0 }
    );
  }, [safeConversations]);

  return (
    <div
      style={{
        padding: "10px 12px",
        margin: "8px",
        border: "1px solid #e5eaf1",
        borderRadius: "10px",
        background: "#f8fafc",
        fontSize: 13,
        color: "#334155"
      }}
    >
      <div style={{ fontWeight: "bold", marginBottom: 6 }}>
        Resumen de selección
      </div>
      <div>Total: <strong>{summary.total}</strong></div>
      <div>Última respuesta = 1: <strong>{summary.one}</strong></div>
      <div>Última respuesta = 2: <strong>{summary.two}</strong></div>
      <div>Otras: <strong>{summary.other}</strong></div>
    </div>
  );
}

export default function ConversationList({
  conversations = [],
  selectedConversationId,
  onSelectConversation
}) {
  const safeConversations = Array.isArray(conversations) ? conversations : [];

  const sortedConversations = useMemo(() => {
    return safeConversations.slice().sort((a, b) => {
      const aNeedsFollowUp = a?.requires_human_follow_up ? 1 : 0;
      const bNeedsFollowUp = b?.requires_human_follow_up ? 1 : 0;

      if (aNeedsFollowUp !== bNeedsFollowUp) {
        return bNeedsFollowUp - aNeedsFollowUp;
      }

      const aDate = new Date(a?.last_message_at || a?.updated_at || a?.created_at || 0).getTime();
      const bDate = new Date(b?.last_message_at || b?.updated_at || b?.created_at || 0).getTime();

      return bDate - aDate;
    });
  }, [safeConversations]);

  return (
    <div className="conversation-list">

      {sortedConversations.map((c) => {
        const needsFollowUp = !!(c?.requires_human_follow_up && c?.status === "open");
        const isSelected = c?.id === selectedConversationId;

        let background = "#fff";
        let borderLeft = "4px solid transparent";

        if (needsFollowUp) {
          background = "#fff1c7";
          borderLeft = "6px solid #e0a100";
        }

        if (isSelected) {
          background = needsFollowUp ? "#ffe69c" : "#eff6ff";
        }

        return (
          <div
            key={c.id}
            onClick={() => onSelectConversation(c.id)}
            style={{
              border: isSelected ? "1px solid #3b82f6" : "1px solid #ccc",
              borderLeft,
              margin: 5,
              padding: 10,
              background,
              cursor: "pointer",
              borderRadius: 10
            }}
          >
            <div>
              <b>#{c.id}</b> ({c.status})
              {needsFollowUp ? (
                <span style={{ marginLeft: 8, fontWeight: "bold", color: "#8a5a00" }}>
                  Pending reply
                </span>
              ) : null}
            </div>

            <div>Panelist: {c.panelist_id}</div>
            <div>Project: {c.project_code}</div>
            {c.panelist_country ? <div>País: {c.panelist_country}</div> : null}
          </div>
        );
      })}
    </div>
  );
}
