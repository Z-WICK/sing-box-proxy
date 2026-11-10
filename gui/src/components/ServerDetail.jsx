import { useState } from 'react';
import { PARAM_PROTOCOLS, PROTOCOL_LABELS, api, stripAnsi } from '../api.js';
import Icon from './Icon.jsx';
import ActionDialog from './ActionDialog.jsx';
import ActionsPanel from './ActionsPanel.jsx';
import OutputModal from './OutputModal.jsx';
import ParamsModal from './ParamsModal.jsx';
import StatusDot, { HEALTH_LABELS, serverHealth } from './StatusDot.jsx';
import TerminalPanel from './TerminalPanel.jsx';

const PROTOCOL_GLYPHS = {
  anytls: 'AT',
  vless_reality: 'VR',
  socks5: 'S5',
  snell: 'SN',
  trusttunnel: 'TT',
  'import-http': 'HT',
  'sing-box': 'SB',
};

function timeAgo(iso) {
  if (!iso) return '—';
  const seconds = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return '刚刚';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`;
  return new Date(iso).toLocaleTimeString();
}

const ACTION_DONE = { start: '已启动', stop: '已停止', restart: '已重启' };

export default function ServerDetail({ server, status, notify, onRefresh, onEdit, onDelete }) {
  const [tab, setTab] = useState('services');
  const [output, setOutput] = useState(null);
  const [action, setAction] = useState(null); // { id, installed }
  const [busy, setBusy] = useState(''); // `${unit}:${action}`
  const [syncing, setSyncing] = useState(false);

  const info = status?.data;
  const services = info?.services || [];
  const health = serverHealth(status);
  const running = services.filter((s) => s.active === 'active').length;

  async function showOutput(title, loader, meta = {}) {
    setOutput({ ...meta, title, text: '', loading: true, error: '' });
    try {
      const text = await loader();
      setOutput({ ...meta, title, text: stripAnsi(text).replace(/^\s*\n/, '').trimEnd(), loading: false, error: '' });
    } catch (err) {
      setOutput({ ...meta, title, text: '', loading: false, error: err.message });
    }
  }

  async function serviceAction(unit, action) {
    if (action === 'stop' && !window.confirm(`停止 ${unit}？正在使用这个节点的客户端会断开。`)) return;
    setBusy(`${unit}:${action}`);
    try {
      await api.service(server.id, unit, action);
      notify(`${unit} ${ACTION_DONE[action]}`, 'success');
      await onRefresh();
    } catch (err) {
      notify(`${unit} 操作失败：${err.message}`, 'error');
    } finally {
      setBusy('');
    }
  }

  async function syncScripts() {
    setSyncing(true);
    try {
      await api.syncServer(server.id);
      notify('脚本已同步到服务器', 'success');
      await onRefresh();
    } catch (err) {
      notify(`同步失败：${err.message}`, 'error');
    } finally {
      setSyncing(false);
    }
  }

  const address = `${server.user ? `${server.user}@` : ''}${server.host}${server.port ? `:${server.port}` : ''}`;

  return (
    <div className="page">
      <header className="detail-header">
        <div className="detail-title">
          <div className={`health-badge badge-${health}`}>
            <StatusDot health={health} />
            {HEALTH_LABELS[health]}
          </div>
          <h1>{server.name}</h1>
          <p className="detail-addr mono">{address}</p>
        </div>
        <div className="actions">
          <button type="button" className="btn" onClick={onRefresh} disabled={status?.loading}>
            <Icon name="refresh" className={status?.loading ? 'spin' : ''} />
            {status?.loading ? '检测中' : '重新检测'}
          </button>
          <button type="button" className="btn" onClick={syncScripts} disabled={syncing} title="把本地 scripts/ 和 tools/ 推送到服务器">
            <Icon name="sync" className={syncing ? 'spin' : ''} />
            同步脚本
          </button>
          <button type="button" className="icon-btn" onClick={onEdit} title="编辑连接信息" aria-label="编辑连接信息">
            <Icon name="edit" />
          </button>
          <button type="button" className="icon-btn danger" onClick={onDelete} title="从控制台移除" aria-label="从控制台移除">
            <Icon name="trash" />
          </button>
        </div>
      </header>

      {status?.error && (
        <div className="banner error">
          <Icon name="unplug" />
          <span>{status.error}</span>
        </div>
      )}

      <dl className="facts">
        <div>
          <dt>系统</dt>
          <dd>{info ? `${info.os || 'Linux'}（${info.arch}）` : '—'}</dd>
        </div>
        <div>
          <dt>公网地址</dt>
          <dd className="mono">{info?.server_identity || '—'}</dd>
        </div>
        <div>
          <dt>sing-box</dt>
          <dd>{info ? (info.singbox.installed ? info.singbox.version : '未安装') : '—'}</dd>
        </div>
        <div>
          <dt>服务</dt>
          <dd>{info ? `${running} 个运行中，共 ${services.length} 个` : '—'}</dd>
        </div>
        <div>
          <dt>上次检测</dt>
          <dd>{timeAgo(status?.checkedAt)}</dd>
        </div>
      </dl>

      <div className="tabs" role="tablist">
        <button type="button" role="tab" aria-selected={tab === 'services'} className={tab === 'services' ? 'active' : ''} onClick={() => setTab('services')}>
          服务
          {info && <span className="tab-count">{services.length}</span>}
        </button>
        <button type="button" role="tab" aria-selected={tab === 'manage'} className={tab === 'manage' ? 'active' : ''} onClick={() => setTab('manage')}>
          安装与配置
        </button>
        <button type="button" role="tab" aria-selected={tab === 'terminal'} className={tab === 'terminal' ? 'active' : ''} onClick={() => setTab('terminal')}>
          终端
        </button>
      </div>

      <div hidden={tab !== 'services'}>
        {info && services.length === 0 && (
          <div className="empty compact">
            <h2>这台服务器上还没有代理服务</h2>
            <p>在「安装与配置」里选择要部署的协议，表单填好后会直接在服务器上执行。</p>
            <button type="button" className="btn primary" onClick={() => setTab('manage')}>
              <Icon name="plus" />
              安装协议
            </button>
          </div>
        )}
        {!info && !status?.error && <div className="skeleton-list"><span /><span /></div>}

        {services.length > 0 && (
          <ul className="service-list">
            {services.map((svc) => {
              const isRunning = svc.active === 'active';
              const label = PROTOCOL_LABELS[svc.protocol] || svc.protocol;
              const isBusy = busy.startsWith(`${svc.unit}:`);
              return (
                <li key={svc.unit} className="service-row">
                  <span className={`proto-tile proto-${svc.protocol}`} aria-hidden="true">
                    {PROTOCOL_GLYPHS[svc.protocol] || '··'}
                  </span>
                  <div className="service-info">
                    <div className="service-name">
                      {label}
                      <span className={`state ${isRunning ? 'state-on' : 'state-off'}`}>
                        {isRunning ? '运行中' : svc.active === 'inactive' ? '已停止' : svc.active || '未知'}
                      </span>
                      {svc.enabled !== 'enabled' && <span className="state state-muted">未设开机自启</span>}
                    </div>
                    <div className="service-unit mono">
                      {svc.unit}
                      {svc.config && <span className="muted"> {svc.config}</span>}
                    </div>
                  </div>
                  <div className="service-actions">
                    {PARAM_PROTOCOLS.has(svc.protocol) && (
                      <button
                        type="button"
                        className="btn small"
                        onClick={() =>
                          showOutput(`${label} 连接参数`, async () => (await api.params(server.id, svc.protocol, svc.unit)).output, {
                            kind: 'params',
                            protocol: svc.protocol,
                            unit: svc.unit,
                          })
                        }
                      >
                        <Icon name="key" size={14} />
                        连接参数
                      </button>
                    )}
                    <button
                      type="button"
                      className="icon-btn"
                      title="查看日志"
                      aria-label={`查看 ${svc.unit} 日志`}
                      onClick={() => showOutput(`${svc.unit} 日志`, async () => (await api.logs(server.id, svc.unit, 300)).output)}
                    >
                      <Icon name="logs" />
                    </button>
                    {isRunning ? (
                      <>
                        <button
                          type="button"
                          className="icon-btn"
                          title="重启"
                          aria-label={`重启 ${svc.unit}`}
                          disabled={isBusy}
                          onClick={() => serviceAction(svc.unit, 'restart')}
                        >
                          <Icon name="restart" className={busy === `${svc.unit}:restart` ? 'spin' : ''} />
                        </button>
                        <button
                          type="button"
                          className="icon-btn danger"
                          title="停止"
                          aria-label={`停止 ${svc.unit}`}
                          disabled={isBusy}
                          onClick={() => serviceAction(svc.unit, 'stop')}
                        >
                          <Icon name="stop" />
                        </button>
                      </>
                    ) : (
                      <button type="button" className="btn small primary" disabled={isBusy} onClick={() => serviceAction(svc.unit, 'start')}>
                        <Icon name="play" size={14} />
                        启动
                      </button>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div hidden={tab !== 'manage'}>
        <ActionsPanel
          info={info}
          onAction={(id, installed) => setAction({ id, installed })}
          onOpenTerminal={() => setTab('terminal')}
        />
      </div>

      <div hidden={tab !== 'terminal'}>
        <TerminalPanel server={server} visible={tab === 'terminal'} onSessionEnd={onRefresh} />
      </div>

      {action && (
        <ActionDialog
          key={action.id}
          server={server}
          actionId={action.id}
          installed={action.installed}
          onClose={() => setAction(null)}
          onFinished={onRefresh}
          onShowParams={(protocol) => {
            setAction(null);
            showOutput(`${PROTOCOL_LABELS[protocol]} 连接参数`, async () => (await api.params(server.id, protocol)).output, {
              kind: 'params',
              protocol,
              unit: services.find((s) => s.protocol === protocol)?.unit || '',
            });
          }}
        />
      )}
      {output?.kind === 'params' && <ParamsModal {...output} onClose={() => setOutput(null)} />}
      {output && output.kind !== 'params' && <OutputModal {...output} onClose={() => setOutput(null)} />}
    </div>
  );
}
