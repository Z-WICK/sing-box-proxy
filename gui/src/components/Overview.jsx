import { PROTOCOL_LABELS } from '../api.js';
import Icon from './Icon.jsx';
import StatusDot, { HEALTH_LABELS, serverHealth } from './StatusDot.jsx';

const ORDER = ['up', 'warn', 'down', 'unknown'];

function FleetBar({ servers, statuses }) {
  const counts = { up: 0, warn: 0, down: 0, unknown: 0 };
  const byHealth = { up: [], warn: [], down: [], unknown: [] };
  for (const s of servers) {
    const h = serverHealth(statuses[s.id]);
    counts[h] += 1;
    byHealth[h].push(s);
  }
  const total = servers.length;

  return (
    <section className="fleet" aria-label="节点健康概况">
      <div className="fleet-headline">
        <span className="fleet-total">{total}</span>
        <span className="fleet-caption">
          台服务器
          {total > 0 && (counts.unknown > 0 ? '，正在检测' : counts.down + counts.warn === 0 ? '，全部正常' : '，需要关注')}
        </span>
      </div>
      <div className="fleet-bar" role="img" aria-label={ORDER.map((h) => `${HEALTH_LABELS[h]} ${counts[h]}`).join('，')}>
        {ORDER.flatMap((h) =>
          byHealth[h].map((s) => <span key={s.id} className={`fleet-seg seg-${h}`} title={`${s.name}：${HEALTH_LABELS[h]}`} />),
        )}
        {total === 0 && <span className="fleet-seg seg-empty" />}
      </div>
      <dl className="fleet-legend">
        {ORDER.map((h) => (
          <div key={h} className={counts[h] === 0 ? 'zero' : ''}>
            <dt>
              <StatusDot health={h} />
              {HEALTH_LABELS[h]}
            </dt>
            <dd>{counts[h]}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function formatMs(ms) {
  if (ms == null) return '';
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)} s` : `${ms} ms`;
}

export default function Overview({ loaded, servers, statuses, onSelect, onAdd, onRefreshAll }) {
  const anyLoading = servers.some((s) => statuses[s.id]?.loading);

  return (
    <div className="page">
      <header className="page-header">
        <h1>全部节点</h1>
        <div className="actions">
          <button type="button" className="btn" onClick={onRefreshAll} disabled={anyLoading || servers.length === 0}>
            <Icon name="refresh" className={anyLoading ? 'spin' : ''} />
            {anyLoading ? '检测中' : '重新检测'}
          </button>
        </div>
      </header>

      <FleetBar servers={servers} statuses={statuses} />

      {loaded && servers.length === 0 ? (
        <div className="empty">
          <Icon name="server" size={28} />
          <h2>还没有服务器</h2>
          <p>
            从 <code>~/.ssh/config</code> 里勾选主机即可添加。控制台用你本机的 SSH 连接，首次操作时会把脚本同步到服务器的
            <code>/root/sing-box-proxy</code>。
          </p>
          <button type="button" className="btn primary" onClick={onAdd}>
            <Icon name="plus" />
            添加服务器
          </button>
        </div>
      ) : (
        <div className="node-list" role="list">
          {servers.map((server) => {
            const status = statuses[server.id];
            const info = status?.data;
            const services = (info?.services || []).filter((s) => s.protocol !== 'import-http');
            const health = serverHealth(status);
            return (
              <button
                type="button"
                role="listitem"
                key={server.id}
                className={`node-row health-${health}`}
                onClick={() => onSelect(server.id)}
              >
                <span className="node-main">
                  <StatusDot status={status} />
                  <span className="node-name">{server.name}</span>
                  <span className="node-addr mono">
                    {info?.server_identity || server.host}
                  </span>
                </span>

                <span className="node-detail">
                  {status?.error ? (
                    <span className="node-error">{status.error}</span>
                  ) : info ? (
                    <>
                      <span className="node-meta">
                        <span>{info.os?.replace(/ GNU\/Linux/, '') || 'Linux'}</span>
                        <span className="sep" />
                        <span>{info.singbox.installed ? `sing-box ${info.singbox.version}` : '未安装 sing-box'}</span>
                      </span>
                      <span className="node-tags">
                        {services.length === 0 && <span className="muted">暂无服务</span>}
                        {services.map((s) => (
                          <span key={s.unit} className={`chip proto-${s.protocol} ${s.active === 'active' ? '' : 'chip-off'}`}>
                            {PROTOCOL_LABELS[s.protocol] || s.protocol}
                          </span>
                        ))}
                      </span>
                    </>
                  ) : (
                    <span className="muted">正在连接…</span>
                  )}
                </span>

                <span className="node-latency mono" title="完成一次状态检测的耗时（含 SSH 连接）">
                  {status?.loading ? <span className="loader" /> : formatMs(status?.elapsedMs)}
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
