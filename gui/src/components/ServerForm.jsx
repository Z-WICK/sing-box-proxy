import { useEffect, useMemo, useState } from 'react';
import { api } from '../api.js';

const AGENT_LABELS = { '1password': '1Password', agent: 'ssh-agent', none: '无 Agent' };

function HostPicker({ existingHosts, onSave, onCancel, onManual }) {
  const [hosts, setHosts] = useState(null);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState('');
  const [selected, setSelected] = useState(() => new Set());
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    api
      .sshHosts()
      .then(({ hosts: list }) => setHosts(list))
      .catch((err) => setError(err.message));
  }, []);

  const existing = useMemo(() => new Set(existingHosts), [existingHosts]);
  const visible = useMemo(() => {
    const q = filter.trim().toLowerCase();
    return (hosts || []).filter(
      (h) => !q || h.alias.toLowerCase().includes(q) || h.hostname.toLowerCase().includes(q),
    );
  }, [hosts, filter]);

  function toggle(alias) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(alias)) next.delete(alias);
      else next.add(alias);
      return next;
    });
  }

  async function submit(e) {
    e.preventDefault();
    if (selected.size === 0) return;
    setSaving(true);
    setError('');
    try {
      // 只保存别名：HostName / User / Port / IdentityAgent 继续由 ~/.ssh/config 决定。
      await onSave([...selected].map((alias) => ({ name: alias, host: alias })));
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  }

  const uses1Password = (hosts || []).some((h) => h.agent === '1password');

  return (
    <form className="modal wide" onSubmit={submit}>
      <div className="modal-head">
        <h2>从 SSH 配置添加服务器</h2>
        <button type="button" className="btn small" onClick={onManual}>
          手动填写
        </button>
      </div>
      <p className="muted small">
        读取自 <code>~/.ssh/config</code>。只保存别名，连接时沿用该别名的 HostName、User、端口和密钥配置。
        {uses1Password && ' 检测到 1Password SSH Agent：连接时 1Password 会弹窗请求授权（Touch ID）。'}
      </p>
      <input
        className="search"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
        placeholder="搜索别名或地址"
        autoFocus
      />
      {error && <div className="banner error">{error}</div>}
      {!hosts && !error && <p className="muted">正在读取 SSH 配置…</p>}
      {hosts && hosts.length === 0 && (
        <p className="muted">
          ~/.ssh/config 中没有可用的 Host 别名。
          <button type="button" className="link" onClick={onManual}>
            手动填写
          </button>
        </p>
      )}
      {visible.length > 0 && (
        <div className="host-list">
          {visible.map((h) => {
            const added = existing.has(h.alias);
            return (
              <label key={h.alias} className={`host-row ${added ? 'disabled' : ''}`}>
                <input
                  type="checkbox"
                  checked={added || selected.has(h.alias)}
                  disabled={added}
                  onChange={() => toggle(h.alias)}
                />
                <span className="host-alias">{h.alias}</span>
                <span className="muted small mono host-target">
                  {h.user ? `${h.user}@` : ''}
                  {h.hostname}
                  {h.port && h.port !== 22 ? `:${h.port}` : ''}
                </span>
                <span className={`tag ${h.agent === '1password' ? 'tag-1p' : ''}`}>{AGENT_LABELS[h.agent] || h.agent}</span>
                {added && <span className="muted small">已添加</span>}
              </label>
            );
          })}
        </div>
      )}
      <div className="modal-actions">
        <span className="muted small grow">{selected.size > 0 && `已选择 ${selected.size} 台`}</span>
        <button type="button" className="btn" onClick={onCancel}>
          取消
        </button>
        <button type="submit" className="btn primary" disabled={saving || selected.size === 0}>
          {saving ? '添加中…' : `添加所选${selected.size ? ` (${selected.size})` : ''}`}
        </button>
      </div>
    </form>
  );
}

function ManualForm({ initial, onCancel, onSave, onPicker }) {
  const [form, setForm] = useState({
    name: initial?.name || '',
    host: initial?.host || '',
    port: initial?.port ? String(initial.port) : '',
    user: initial?.user || '',
    identityFile: initial?.identityFile || '',
  });
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  const set = (key) => (e) => setForm((prev) => ({ ...prev, [key]: e.target.value }));

  async function submit(e) {
    e.preventDefault();
    setSaving(true);
    setError('');
    try {
      await onSave(form);
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  }

  return (
    <form className="modal" onSubmit={submit}>
      <div className="modal-head">
        <h2>{initial ? '编辑服务器' : '手动添加服务器'}</h2>
        {onPicker && (
          <button type="button" className="btn small" onClick={onPicker}>
            从 SSH 配置选择
          </button>
        )}
      </div>
      <label>
        名称
        <input value={form.name} onChange={set('name')} placeholder="东京-1" required autoFocus />
      </label>
      <label>
        主机
        <input value={form.host} onChange={set('host')} placeholder="203.0.113.10 或 ~/.ssh/config 中的别名" required />
      </label>
      <div className="row">
        <label>
          端口
          <input value={form.port} onChange={set('port')} placeholder="22" inputMode="numeric" />
        </label>
        <label>
          用户
          <input value={form.user} onChange={set('user')} placeholder="root" />
        </label>
      </div>
      <label>
        密钥路径（可选）
        <input value={form.identityFile} onChange={set('identityFile')} placeholder="~/.ssh/id_ed25519 或 1Password 导出的 .pub" />
      </label>
      <p className="muted small">
        留空的字段沿用 <code>~/.ssh/config</code> 和 SSH Agent。使用 1Password 时密钥路径留空即可；
        如需指定某把钥匙，请填它的 <code>.pub</code> 公钥文件。非 root 用户需要免密 sudo。
      </p>
      {error && <div className="banner error">{error}</div>}
      <div className="modal-actions">
        <button type="button" className="btn" onClick={onCancel}>
          取消
        </button>
        <button type="submit" className="btn primary" disabled={saving}>
          {saving ? '保存中…' : '保存'}
        </button>
      </div>
    </form>
  );
}

export default function ServerForm({ initial, existingHosts = [], onCancel, onSave }) {
  const [mode, setMode] = useState(initial ? 'manual' : 'picker');

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onCancel()}>
      {mode === 'picker' ? (
        <HostPicker existingHosts={existingHosts} onSave={onSave} onCancel={onCancel} onManual={() => setMode('manual')} />
      ) : (
        <ManualForm
          initial={initial}
          onSave={onSave}
          onCancel={onCancel}
          onPicker={initial ? null : () => setMode('picker')}
        />
      )}
    </div>
  );
}
