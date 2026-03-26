export default function ConversationList({
  conversations,
  selectedConversationId,
  onSelectConversation
}) {
  return (
    <div>
      {conversations.map((c) => (
        <div
          key={c.id}
          onClick={() => onSelectConversation(c.id)}
          style={{
            border: "1px solid #ccc",
            margin: 5,
            padding: 10,
            background: c.id === selectedConversationId ? "#eee" : "#fff",
            cursor: "pointer"
          }}
        >
          <div><b>#{c.id}</b> ({c.status})</div>
          <div>Panelist: {c.panelist_id}</div>
          <div>Project: {c.project_code}</div>
        </div>
      ))}
    </div>
  );
}
