import { useState } from 'react';
import { ACTIONS, PROTOCOLS, SECONDARY_ACTIONS } from '../actions.js';
import Icon from './Icon.jsx';

const GLYPHS = { anytls: 'AT', vless_reality: 'VR', socks5: 'S5', snell: 'SN', trusttunnel: 'TT' };

function stateOf(services, protocol) {
  const svc = services.find((s) => s.protocol === protocol);
  if (!svc) return { installed: false, label: '未安装', tone: 'none' };
  if (svc.active === 'active') return { installed: true, label: '运行中', tone: 'on', unit: svc.unit };
  return { installed: true, label: '已停止', tone: 'off', unit: svc.unit };
}

export default function ActionsPanel({ info, onAction, onOpenTerminal }) {
  const [menuFor, setMenuFor] = useState('');
  const services = info?.services || [];
  const singbox = info?.singbox;

  if (!info) {
    return (
      <div className="skeleton-list">
        <span />
        <span />
        <span />
      </div>
    );
  }

  return (
    <div className="actions-panel">
      <section className="core-card">
        <div className="core-main">
          <span className="proto-tile proto-sing-box" aria-hidden="true">
            SB
          </span>
          <div>
            <h3>sing-box 核心</h3>
            <p>{singbox.installed ? `已安装 ${singbox.version}，AnyTLS、VLESS Reality 和 SOCKS5 依赖它运行。` : '还没有安装。AnyTLS、VLESS Reality 和 SOCKS5 需要先装好 sing-box。'}</p>
          </div>
        </div>
        <div className="core-actions">
          {singbox.installed ? (
            <>
              <button type="button" className="btn" onClick={() => onAction('singbox.update', true)}>
                <Icon name="sync" />
                更新
              </button>
              <button type="button" className="icon-btn danger" title="完整卸载 sing-box" aria-label="完整卸载 sing-box" onClick={() => onAction('singbox.uninstall', true)}>
                <Icon name="trash" />
              </button>
            </>
          ) : (
            <button type="button" className="btn primary" onClick={() => onAction('singbox.install', false)}>
              <Icon name="plus" />
              安装 sing-box
            </button>
          )}
        </div>
      </section>

      <div className="proto-grid">
        {PROTOCOLS.map((p) => {
          const state = stateOf(services, p.id);
          const blocked = p.needsSingbox && !singbox.installed;
          const secondary = state.installed ? SECONDARY_ACTIONS[p.id] || [] : [];
          return (
            <article key={p.id} className={`proto-card proto-${p.id}`}>
              <header>
                <span className="proto-tile" aria-hidden="true">
                  {GLYPHS[p.id]}
                </span>
                <h3>{p.name}</h3>
                <span className={`proto-state state-${state.tone}`}>{state.label}</span>
              </header>
              <p className="proto-summary">{p.summary}</p>
              <footer>
                <button
                  type="button"
                  className={`btn small ${state.installed ? '' : 'primary'}`}
                  disabled={blocked}
                  title={blocked ? '请先安装 sing-box' : undefined}
                  onClick={() => onAction(`${p.id}.configure`, state.installed)}
                >
                  <Icon name={state.installed ? 'edit' : 'plus'} size={14} />
                  {state.installed ? '重新配置' : '安装'}
                </button>
                {blocked && <span className="blocked-hint">需要先安装 sing-box</span>}
                {secondary.length > 0 && (
                  <div className="more">
                    <button
                      type="button"
                      className="icon-btn"
                      aria-haspopup="menu"
                      aria-expanded={menuFor === p.id}
                      aria-label={`${p.name} 更多操作`}
                      onClick={() => setMenuFor(menuFor === p.id ? '' : p.id)}
                      onBlur={() => setTimeout(() => setMenuFor((m) => (m === p.id ? '' : m)), 150)}
                    >
                      <Icon name="more" />
                    </button>
                    {menuFor === p.id && (
                      <div className="menu" role="menu">
                        {secondary.map((id) => (
                          <button
                            type="button"
                            role="menuitem"
                            key={id}
                            className={ACTIONS[id].danger ? 'danger' : ''}
                            onMouseDown={(e) => e.preventDefault()}
                            onClick={() => {
                              setMenuFor('');
                              onAction(id, state.installed);
                            }}
                          >
                            {ACTIONS[id].title}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </footer>
            </article>
          );
        })}
      </div>

      <p className="hint">
        需要更细的控制？
        <button type="button" className="link" onClick={onOpenTerminal}>
          打开终端
        </button>
        运行原始的交互菜单。
      </p>
    </div>
  );
}
