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
      project_code: ""
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
        <label>Project code</label>
        <input
          value={filters.project_code}
          onChange={(e) => updateField("project_code", e.target.value)}
        />
      </div>

      <button onClick={clearFilters}>Limpiar</button>
    </div>
  );
}
