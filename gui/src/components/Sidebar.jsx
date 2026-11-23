import Icon from './Icon.jsx';
import StatusDot from './StatusDot.jsx';

const THEMES = [
  { id: 'light', icon: 'sun', label: '浅色' },
  { id: 'system', icon: 'monitor', label: '跟随系统' },
  { id: 'dark', icon: 'moon', label: '深色' },
];

export default function Sidebar({ servers, statuses, selectedId, anyLoading, theme = 'system', onThemeChange, onSelect, onAdd }) {
  return (
    <aside className="sidebar">
      <div className="brand">
        <svg className={`brand-mark ${anyLoading ? 'is-busy' : ''}`} viewBox="0 0 32 32" aria-hidden="true">
          <circle className="brand-ring-outer" cx="16" cy="16" r="14" fill="none" strokeWidth="1.5" />
          <circle className="brand-ring-mid" cx="16" cy="16" r="9.5" fill="none" strokeWidth="1.8" />
          <circle className="brand-core" cx="16" cy="16" r="4.5" />
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
        {servers.map((server, idx) => (
          <button
            type="button"
            key={server.id}
            style={{ '--i': idx }}
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

      <div className="sidebar-footer">
        <button type="button" className="btn add-btn" onClick={onAdd}>
          <Icon name="plus" />
          添加服务器
        </button>

        {onThemeChange && (
          <div className="theme-switch" role="group" aria-label="界面主题">
            {THEMES.map((item) => (
              <button
                key={item.id}
                type="button"
                className={theme === item.id ? 'active' : ''}
                aria-pressed={theme === item.id}
                title={item.label}
                aria-label={item.label}
                onClick={() => onThemeChange(item.id)}
              >
                <Icon name={item.icon} size={14} />
              </button>
            ))}
          </div>
        )}
      </div>
    </aside>
  );
}
