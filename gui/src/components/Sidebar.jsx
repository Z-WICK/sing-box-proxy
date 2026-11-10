import StatusDot from './StatusDot.jsx';

export default function Sidebar({ servers, statuses, selectedId, onSelect, onAdd }) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <span className="brand-mark">◆</span>
        <span>sing-box-proxy</span>
      </div>
      <button
        type="button"
        className={`nav-item ${selectedId === null ? 'active' : ''}`}
        onClick={() => onSelect(null)}
      >
        全部服务器
        <span className="nav-count">{servers.length}</span>
      </button>
      <div className="nav-section">服务器</div>
      <nav className="nav-list">
        {servers.map((server) => (
          <button
            type="button"
            key={server.id}
            className={`nav-item ${selectedId === server.id ? 'active' : ''}`}
            onClick={() => onSelect(server.id)}
          >
            <StatusDot status={statuses[server.id]} />
            <span className="nav-text">
              <span className="nav-name">{server.name}</span>
              <span className="nav-host">{server.host}</span>
            </span>
          </button>
        ))}
        {servers.length === 0 && <p className="muted small pad">还没有服务器</p>}
      </nav>
      <button type="button" className="btn primary block" onClick={onAdd}>
        + 添加服务器
      </button>
    </aside>
  );
}
