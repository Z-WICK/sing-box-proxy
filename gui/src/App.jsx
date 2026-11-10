import { useCallback, useEffect, useRef, useState } from 'react';
import { api, hasToken } from './api.js';
import Overview from './components/Overview.jsx';
import ServerDetail from './components/ServerDetail.jsx';
import ServerForm from './components/ServerForm.jsx';
import Sidebar from './components/Sidebar.jsx';
import Toasts from './components/Toasts.jsx';

export default function App() {
  const [servers, setServers] = useState([]);
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [selectedId, setSelectedId] = useState(null);
  const [statuses, setStatuses] = useState({});
  const [editing, setEditing] = useState(null); // null | 'new' | server
  const [toasts, setToasts] = useState([]);
  const toastSeq = useRef(0);

  const notify = useCallback((text, kind = 'info') => {
    const id = ++toastSeq.current;
    setToasts((prev) => [...prev, { id, text, kind }]);
    setTimeout(() => setToasts((prev) => prev.filter((t) => t.id !== id)), kind === 'error' ? 7000 : 3500);
  }, []);

  const dismissToast = useCallback((id) => setToasts((prev) => prev.filter((t) => t.id !== id)), []);

  const refreshStatus = useCallback(async (id) => {
    setStatuses((prev) => ({ ...prev, [id]: { ...prev[id], loading: true } }));
    const started = performance.now();
    try {
      const data = await api.status(id);
      setStatuses((prev) => ({
        ...prev,
        [id]: {
          loading: false,
          data: data.status,
          error: '',
          checkedAt: data.checkedAt,
          elapsedMs: Math.round(performance.now() - started),
        },
      }));
    } catch (err) {
      setStatuses((prev) => ({
        ...prev,
        [id]: { ...prev[id], loading: false, error: err.message, checkedAt: new Date().toISOString(), elapsedMs: null },
      }));
    }
  }, []);

  // 限制并发：使用 1Password 等需要授权的 SSH Agent 时，避免同时弹出大量授权窗口。
  const refreshAll = useCallback(
    async (list) => {
      const queue = [...list];
      const worker = async () => {
        while (queue.length) await refreshStatus(queue.shift().id);
      };
      await Promise.all(Array.from({ length: Math.min(3, queue.length) }, worker));
    },
    [refreshStatus],
  );

  useEffect(() => {
    if (!hasToken()) return;
    api
      .listServers()
      .then(({ servers: list }) => {
        setServers(list);
        setLoaded(true);
        refreshAll(list);
      })
      .catch((err) => {
        setLoadError(err.message);
        setLoaded(true);
      });
  }, [refreshAll]);

  async function saveServer(form) {
    if (Array.isArray(form)) {
      const { servers: created } = await api.addServers(form);
      setServers((prev) => [...prev, ...created]);
      setSelectedId(created.length === 1 ? created[0].id : null);
      setEditing(null);
      notify(`已添加 ${created.length} 台服务器`, 'success');
      refreshAll(created);
      return;
    }
    if (editing === 'new') {
      const { server } = await api.addServer(form);
      setServers((prev) => [...prev, server]);
      setSelectedId(server.id);
      notify(`已添加 ${server.name}`, 'success');
      refreshStatus(server.id);
    } else {
      const { server } = await api.updateServer(editing.id, form);
      setServers((prev) => prev.map((s) => (s.id === server.id ? server : s)));
      notify(`已保存 ${server.name}`, 'success');
      refreshStatus(server.id);
    }
    setEditing(null);
  }

  async function removeServer(server) {
    if (!window.confirm(`从控制台移除「${server.name}」？\n服务器上的服务和文件不会被改动。`)) return;
    try {
      await api.deleteServer(server.id);
      setServers((prev) => prev.filter((s) => s.id !== server.id));
      setStatuses((prev) => {
        const next = { ...prev };
        delete next[server.id];
        return next;
      });
      setSelectedId(null);
      notify(`已移除 ${server.name}`);
    } catch (err) {
      notify(err.message, 'error');
    }
  }

  if (!hasToken()) {
    return (
      <div className="fatal">
        <h1>需要带令牌的链接</h1>
        <p>
          请复制控制台启动时在终端打印的完整地址（包含 <code>#token=…</code>）来打开本页。令牌每次启动都会重新生成。
        </p>
      </div>
    );
  }

  const selected = servers.find((s) => s.id === selectedId) || null;

  return (
    <div className="layout">
      <Sidebar
        servers={servers}
        statuses={statuses}
        selectedId={selectedId}
        onSelect={setSelectedId}
        onAdd={() => setEditing('new')}
      />
      <main className="main">
        {loadError && <div className="banner error">读取服务器清单失败：{loadError}</div>}
        {selected ? (
          <ServerDetail
            key={selected.id}
            server={selected}
            status={statuses[selected.id]}
            notify={notify}
            onRefresh={() => refreshStatus(selected.id)}
            onEdit={() => setEditing(selected)}
            onDelete={() => removeServer(selected)}
          />
        ) : (
          <Overview
            loaded={loaded}
            servers={servers}
            statuses={statuses}
            onSelect={setSelectedId}
            onAdd={() => setEditing('new')}
            onRefreshAll={() => refreshAll(servers)}
          />
        )}
      </main>
      {editing && (
        <ServerForm
          initial={editing === 'new' ? null : editing}
          existingHosts={servers.map((s) => s.host)}
          onCancel={() => setEditing(null)}
          onSave={saveServer}
        />
      )}
      <Toasts toasts={toasts} onDismiss={dismissToast} />
    </div>
  );
}
