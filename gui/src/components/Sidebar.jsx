import Icon from './Icon.jsx';
import StatusDot from './StatusDot.jsx';

export default function Sidebar({ servers, statuses, selectedId, onSelect, onAdd }) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <svg className="brand-mark" viewBox="0 0 32 32" aria-hidden="true">
          <circle cx="16" cy="16" r="4.5" />
          <circle cx="16" cy="16" r="10" fill="none" strokeWidth="2" />
          <circle cx="16" cy="16" r="15" fill="none" strokeWidth="1.5" opacity="0.45" />
        </svg>
        <div>
          <div className="brand-name">sing-box-proxy</div>
          <div className="brand-sub">节点控制台</div>
        </div>
      </div>

      <button
        type="button"
        className={`nav-item nav-top ${selectedId === null ? 'active' : ''}`}
        onClick={() => onSelect(null)}
        aria-current={selectedId === null ? 'page' : undefined}
      >
        <Icon name="grid" />
        <span className="nav-name">全部节点</span>
        <span className="nav-count">{servers.length}</span>
      </button>

      <nav className="nav-list" aria-label="服务器">
        {servers.map((server) => (
          <button
            type="button"
            key={server.id}
            className={`nav-item ${selectedId === server.id ? 'active' : ''}`}
            onClick={() => onSelect(server.id)}
            aria-current={selectedId === server.id ? 'page' : undefined}
          >
            <StatusDot status={statuses[server.id]} />
            <span className="nav-name">{server.name}</span>
            {server.host !== server.name && <span className="nav-host">{server.host}</span>}
          </button>
        ))}
      </nav>

      <button type="button" className="btn add-btn" onClick={onAdd}>
        <Icon name="plus" />
        添加服务器
      </button>
    </aside>
  );
}
