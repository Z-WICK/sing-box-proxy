import { useState } from 'react';
import { PARAM_PROTOCOLS, PROTOCOL_LABELS, api, stripAnsi } from '../api.js';
import OutputModal from './OutputModal.jsx';
import StatusDot from './StatusDot.jsx';
import TerminalPanel from './TerminalPanel.jsx';

function timeAgo(iso) {
  if (!iso) return '';
  const seconds = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return '刚刚';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`;
  return new Date(iso).toLocaleTimeString();
}

export default function ServerDetail({ server, status, onRefresh, onEdit, onDelete }) {
  const [tab, setTab] = useState('services');
  const [output, setOutput] = useState(null); // { title, text, loading, error }
  const [busyUnit, setBusyUnit] = useState('');
  const [syncing, setSyncing] = useState(false);
  const [notice, setNotice] = useState('');

  const info = status?.data;
  const services = info?.services || [];

  async function showOutput(title, loader) {
    setOutput({ title, text: '', loading: true, error: '' });
    try {
      const text = await loader();
      setOutput({ title, text: stripAnsi(text), loading: false, error: '' });
    } catch (err) {
      setOutput({ title, text: '', loading: false, error: err.message });
    }
  }

  async function serviceAction(unit, action, label) {
    if (action === 'stop' && !window.confirm(`停止 ${unit}？使用该节点的客户端会断开。`)) return;
    setBusyUnit(unit);
    setNotice('');
    try {
      await api.service(server.id, unit, action);
      setNotice(`${unit} 已${label}`);
      await onRefresh();
    } catch (err) {
      setNotice(`操作失败：${err.message}`);
    } finally {
      setBusyUnit('');
    }
  }

  async function forceSync() {
    setSyncing(true);
    setNotice('');
    try {
      await api.syncServer(server.id);
      setNotice('脚本已同步到服务器');
      await onRefresh();
    } catch (err) {
      setNotice(`同步失败：${err.message}`);
    } finally {
      setSyncing(false);
    }
  }

  return (
    <section>
      <header className="page-header">
        <div>
          <h1 className="title-with-dot">
            <StatusDot status={status} />
            {server.name}
          </h1>
          <p className="muted mono small">
            {server.user ? `${server.user}@` : ''}
            {server.host}
            {server.port ? `:${server.port}` : ''}
            {info && ` · ${info.os || 'Linux'} · ${info.arch} · 公网标识 ${info.server_identity}`}
          </p>
        </div>
        <div className="actions">
          <button type="button" className="btn" onClick={onRefresh} disabled={status?.loading}>
            {status?.loading ? '刷新中…' : '刷新'}
          </button>
          <button type="button" className="btn" onClick={forceSync} disabled={syncing} title="把本地 scripts/ 和 tools/ 推送到服务器">
            {syncing ? '同步中…' : '同步脚本'}
          </button>
          <button type="button" className="btn" onClick={onEdit}>
            编辑
          </button>
          <button type="button" className="btn danger-ghost" onClick={onDelete}>
            移除
          </button>
        </div>
      </header>

      {status?.error && <div className="banner error">{status.error}</div>}
      {notice && <div className="banner">{notice}</div>}

      <div className="stats">
        <div className="stat">
          <span className="stat-label">sing-box</span>
          <span className="stat-value">
            {info ? (info.singbox.installed ? info.singbox.version : '未安装') : '—'}
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">运行中的服务</span>
          <span className="stat-value">
            {info ? `${services.filter((s) => s.active === 'active').length} / ${services.length}` : '—'}
          </span>
        </div>
        <div className="stat">
          <span className="stat-label">上次检测</span>
          <span className="stat-value small">{timeAgo(status?.checkedAt) || '—'}</span>
        </div>
      </div>

      <div className="tabs" role="tablist">
        <button type="button" role="tab" aria-selected={tab === 'services'} className={tab === 'services' ? 'active' : ''} onClick={() => setTab('services')}>
          服务
        </button>
        <button type="button" role="tab" aria-selected={tab === 'terminal'} className={tab === 'terminal' ? 'active' : ''} onClick={() => setTab('terminal')}>
          终端 / 配置向导
        </button>
      </div>

      <div hidden={tab !== 'services'}>
        {info && services.length === 0 && (
          <div className="empty">
            <p>这台服务器上还没有由脚本管理的服务。</p>
            <p className="muted small">
              打开「终端 / 配置向导」运行管理菜单：先安装 sing-box，再在 Proxy 菜单中选择协议的配置向导。
            </p>
            <button type="button" className="btn primary" onClick={() => setTab('terminal')}>
              打开管理菜单
            </button>
          </div>
        )}
        {services.length > 0 && (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>服务</th>
                  <th>协议</th>
                  <th>状态</th>
                  <th>开机自启</th>
                  <th className="right">操作</th>
                </tr>
              </thead>
              <tbody>
                {services.map((svc) => {
                  const busy = busyUnit === svc.unit;
                  const running = svc.active === 'active';
                  return (
                    <tr key={svc.unit}>
                      <td>
                        <div className="mono">{svc.unit}</div>
                        {svc.config && <div className="muted small mono">{svc.config}</div>}
                      </td>
                      <td>
                        <span className="tag">{PROTOCOL_LABELS[svc.protocol] || svc.protocol}</span>
                      </td>
                      <td>
                        <span className={`state ${running ? 'state-ok' : 'state-off'}`}>{svc.active || 'unknown'}</span>
                      </td>
                      <td className="small">{svc.enabled || '—'}</td>
                      <td className="right nowrap">
                        {PARAM_PROTOCOLS.has(svc.protocol) && (
                          <button
                            type="button"
                            className="btn small"
                            onClick={() =>
                              showOutput(`${PROTOCOL_LABELS[svc.protocol]} 参数 · ${svc.unit}`, async () => {
                                const r = await api.params(server.id, svc.protocol, svc.unit);
                                return r.output;
                              })
                            }
                          >
                            参数
                          </button>
                        )}
                        <button
                          type="button"
                          className="btn small"
                          onClick={() =>
                            showOutput(`日志 · ${svc.unit}`, async () => (await api.logs(server.id, svc.unit, 300)).output)
                          }
                        >
                          日志
                        </button>
                        {running ? (
                          <>
                            <button type="button" className="btn small" disabled={busy} onClick={() => serviceAction(svc.unit, 'restart', '重启')}>
                              重启
                            </button>
                            <button type="button" className="btn small danger-ghost" disabled={busy} onClick={() => serviceAction(svc.unit, 'stop', '停止')}>
                              停止
                            </button>
                          </>
                        ) : (
                          <button type="button" className="btn small primary" disabled={busy} onClick={() => serviceAction(svc.unit, 'start', '启动')}>
                            启动
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div hidden={tab !== 'terminal'}>
        <TerminalPanel server={server} visible={tab === 'terminal'} onSessionEnd={onRefresh} />
      </div>

      {output && <OutputModal {...output} onClose={() => setOutput(null)} />}
    </section>
  );
}
