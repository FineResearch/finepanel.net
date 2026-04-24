export default function FiltersBar({ filters, onChange }) {
  function updateField(field, value) {
    onChange((prev) => ({
      ...prev,
      [field]: value
    }));
  }

  function clearFilters() {
    onChange({
      status: "",
      project_code: "",
      last_reply_type: "",
      last_reply_answered: "",
      last_reply_window: "",
      country: "",
      limit: "50"
    });
  }

  return (
    <div className="filters-box">
      <h2>Filtros</h2>

      <div className="form-group">
        <label>Estado</label>
        <select
          value={filters.status}
          onChange={(e) => updateField("status", e.target.value)}
        >
          <option value="">Todos</option>
          <option value="open">Open</option>
          <option value="resolved">Resolved</option>
        </select>
      </div>
<div className="form-group">
  <label>Panelist ID</label>
  <input
    value={filters.panelist_id || ""}
    onChange={(e) => updateField("panelist_id", e.target.value)}
  />
</div>


      <div className="form-group">
        <label>Project code</label>
        <input
          value={filters.project_code}
          onChange={(e) => updateField("project_code", e.target.value)}
        />
      </div>

      <div className="form-group">
        <label>País</label>
        <select
          value={filters.country || ""}
          onChange={(e) => updateField("country", e.target.value)}
        >
          <option value="">Todos</option>
          <option value="Brasil">Brasil</option>
          <option value="México">México</option>
          <option value="Colombia">Colombia</option>
          <option value="Argentina">Argentina</option>
          <option value="Costa Rica">Costa Rica</option>
          <option value="Guatemala">Guatemala</option>
          <option value="Panamá">Panamá</option>
          <option value="Honduras">Honduras</option>
          <option value="Nicaragua">Nicaragua</option>
          <option value="El Salvador">El Salvador</option>
          <option value="República Dominicana">República Dominicana</option>
          <option value="Uruguay">Uruguay</option>
          <option value="Paraguay">Paraguay</option>
          <option value="Perú">Perú</option>
          <option value="Chile">Chile</option>
          <option value="Ecuador">Ecuador</option>
          <option value="Venezuela">Venezuela</option>
          <option value="Puerto Rico">Puerto Rico</option>
          <option value="España">España</option>
          <option value="Portugal">Portugal</option>
          <option value="Otro">Otro</option>
        </select>
      </div>

      <div className="form-group">
        <label>Última respuesta</label>
        <select
          value={filters.last_reply_type || ""}
          onChange={(e) => updateField("last_reply_type", e.target.value)}
        >
          <option value="">Todas</option>
          <option value="one">Respondió 1</option>
          <option value="two">Respondió 2</option>
          <option value="other">No es 1 ni 2</option>
        </select>
      </div>

      <div className="form-group">
        <label>¿Última respuesta respondida?</label>
        <select
          value={filters.last_reply_answered || ""}
          onChange={(e) => updateField("last_reply_answered", e.target.value)}
        >
          <option value="">Todas</option>
          <option value="no">No</option>
          <option value="yes">Sí</option>
        </select>
      </div>

      <div className="form-group">
        <label>Momento de última respuesta</label>
        <select
          value={filters.last_reply_window || ""}
          onChange={(e) => updateField("last_reply_window", e.target.value)}
        >
          <option value="">Todas</option>
          <option value="within_24h">Dentro de últimas 24h</option>
          <option value="older">Antes de 24h</option>
        </select>
      </div>

      <div className="form-group">
        <label>Cantidad</label>
        <select
          value={filters.limit || "50"}
          onChange={(e) => updateField("limit", e.target.value)}
        >
          <option value="50">50</option>
          <option value="100">100</option>
          <option value="200">200</option>
        </select>
      </div>

      <button onClick={clearFilters}>Limpiar</button>
    </div>
  );
}
