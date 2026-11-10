import { useCallback, useEffect, useState } from 'react';
import { api, hasToken } from './api.js';
import Overview from './components/Overview.jsx';
import ServerDetail from './components/ServerDetail.jsx';
import ServerForm from './components/ServerForm.jsx';
import Sidebar from './components/Sidebar.jsx';

export default function App() {
  const [servers, setServers] = useState([]);
  const [loadError, setLoadError] = useState('');
  const [selectedId, setSelectedId] = useState(null);
  const [statuses, setStatuses] = useState({});
  const [editing, setEditing] = useState(null); // null | 'new' | server

  const refreshStatus = useCallback(async (id) => {
    setStatuses((prev) => ({ ...prev, [id]: { ...prev[id], loading: true } }));
    try {
      const data = await api.status(id);
      setStatuses((prev) => ({
        ...prev,
        [id]: { loading: false, data: data.status, error: '', checkedAt: data.checkedAt },
      }));
    } catch (err) {
      setStatuses((prev) => ({
        ...prev,
        [id]: { ...prev[id], loading: false, error: err.message, checkedAt: new Date().toISOString() },
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
        refreshAll(list);
      })
      .catch((err) => setLoadError(err.message));
  }, [refreshAll]);

  async function saveServer(form) {
    if (Array.isArray(form)) {
      const { servers: created } = await api.addServers(form);
      setServers((prev) => [...prev, ...created]);
      setSelectedId(created.length === 1 ? created[0].id : null);
      setEditing(null);
      refreshAll(created);
      return;
    }
    if (editing === 'new') {
      const { server } = await api.addServer(form);
      setServers((prev) => [...prev, server]);
      setSelectedId(server.id);
      refreshStatus(server.id);
    } else {
      const { server } = await api.updateServer(editing.id, form);
      setServers((prev) => prev.map((s) => (s.id === server.id ? server : s)));
      refreshStatus(server.id);
    }
    setEditing(null);
  }

  async function deleteServer(server) {
    if (!window.confirm(`从控制台移除「${server.name}」？\n（不会改动服务器上的任何内容）`)) return;
    await api.deleteServer(server.id);
    setServers((prev) => prev.filter((s) => s.id !== server.id));
    setStatuses((prev) => {
      const next = { ...prev };
      delete next[server.id];
      return next;
    });
    setSelectedId(null);
  }

  if (!hasToken()) {
    return (
      <div className="fatal">
        <h1>缺少访问令牌</h1>
        <p>请使用控制台启动时在终端打印的完整链接（包含 <code>#token=…</code>）打开本页面。</p>
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
        {loadError && <div className="banner error">{loadError}</div>}
        {selected ? (
          <ServerDetail
            key={selected.id}
            server={selected}
            status={statuses[selected.id]}
            onRefresh={() => refreshStatus(selected.id)}
            onEdit={() => setEditing(selected)}
            onDelete={() => deleteServer(selected).catch((err) => window.alert(err.message))}
          />
        ) : (
          <Overview
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
    </div>
  );
}
