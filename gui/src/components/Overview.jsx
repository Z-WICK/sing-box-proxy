import { PROTOCOL_LABELS } from '../api.js';
import StatusDot from './StatusDot.jsx';

export default function Overview({ servers, statuses, onSelect, onAdd, onRefreshAll }) {
  const anyLoading = servers.some((s) => statuses[s.id]?.loading);

  return (
    <section>
      <header className="page-header">
        <div>
          <h1>全部服务器</h1>
          <p className="muted">通过本机 SSH 连接管理，服务器上不会额外开放端口。</p>
        </div>
        <div className="actions">
          <button type="button" className="btn" onClick={onRefreshAll} disabled={anyLoading || servers.length === 0}>
            {anyLoading ? '刷新中…' : '全部刷新'}
          </button>
        </div>
      </header>

      {servers.length === 0 ? (
        <div className="empty">
          <h2>添加第一台服务器</h2>
          <p className="muted">
            需要能用 SSH 密钥登录（root，或有免密 sudo 的用户）。控制台会自动把本地脚本同步到服务器的
            <code>/root/sing-box-proxy</code>。
          </p>
          <button type="button" className="btn primary" onClick={onAdd}>
            + 添加服务器
          </button>
        </div>
      ) : (
        <div className="card-grid">
          {servers.map((server) => {
            const status = statuses[server.id];
            const services = (status?.data?.services || []).filter((s) => s.protocol !== 'import-http');
            const running = services.filter((s) => s.active === 'active').length;
            return (
              <button type="button" key={server.id} className="card server-card" onClick={() => onSelect(server.id)}>
                <div className="card-title">
                  <StatusDot status={status} />
                  <strong>{server.name}</strong>
                </div>
                <div className="muted small mono">
                  {server.user ? `${server.user}@` : ''}
                  {server.host}
                  {server.port ? `:${server.port}` : ''}
                </div>
                {status?.error ? (
                  <p className="error-text small">{status.error}</p>
                ) : status?.data ? (
                  <>
                    <div className="small">
                      sing-box {status.data.singbox.installed ? status.data.singbox.version : '未安装'} ·{' '}
                      {running}/{services.length} 个服务运行中
                    </div>
                    <div className="tags">
                      {services.map((s) => (
                        <span key={s.unit} className={`tag ${s.active === 'active' ? 'tag-ok' : 'tag-off'}`}>
                          {PROTOCOL_LABELS[s.protocol] || s.protocol}
                        </span>
                      ))}
                    </div>
                  </>
                ) : (
                  <p className="muted small">检测中…</p>
                )}
              </button>
            );
          })}
        </div>
      )}
    </section>
  );
}
