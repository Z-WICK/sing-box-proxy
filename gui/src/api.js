const TOKEN_KEY = 'sbp-gui-token';
let token = '';

/** 从启动链接的 #token=... 读取令牌，存入 sessionStorage 并从地址栏移除。 */
export function initToken() {
  const match = window.location.hash.match(/token=([A-Za-z0-9]+)/);
  if (match) {
    token = match[1];
    try {
      sessionStorage.setItem(TOKEN_KEY, token);
    } catch {
      // 隐私模式下 sessionStorage 不可用时只保留在内存中
    }
    window.history.replaceState(null, '', window.location.pathname + window.location.search);
  } else {
    try {
      token = sessionStorage.getItem(TOKEN_KEY) || '';
    } catch {
      token = '';
    }
  }
  return token;
}

export function hasToken() {
  return Boolean(token);
}

async function request(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: {
      'x-sbp-token': token,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try {
    data = await res.json();
  } catch {
    // 非 JSON 响应
  }
  if (!res.ok) {
    throw new Error(data.error || `请求失败 (${res.status})`);
  }
  return data;
}

export const api = {
  listServers: () => request('GET', '/api/servers'),
  addServer: (server) => request('POST', '/api/servers', server),
  addServers: (servers) => request('POST', '/api/servers/batch', { servers }),
  sshHosts: () => request('GET', '/api/ssh-hosts'),
  updateServer: (id, server) => request('PUT', `/api/servers/${id}`, server),
  deleteServer: (id) => request('DELETE', `/api/servers/${id}`),
  syncServer: (id) => request('POST', `/api/servers/${id}/sync`),
  status: (id) => request('GET', `/api/servers/${id}/status`),
  params: (id, protocol, unit) =>
    request('GET', `/api/servers/${id}/params/${protocol}${unit ? `?unit=${encodeURIComponent(unit)}` : ''}`),
  service: (id, unit, action) => request('POST', `/api/servers/${id}/service`, { unit, action }),
  logs: (id, unit, lines = 200) =>
    request('GET', `/api/servers/${id}/logs?unit=${encodeURIComponent(unit)}&lines=${lines}`),
};

const EXIT_MARK = '\u0000SBP_EXIT:';

/**
 * 执行远端操作并实时回调输出。返回退出码（0 表示成功）。
 * 服务端在输出末尾追加 `\0SBP_EXIT:<code>` 作为结束标记。
 */
export async function runAction(serverId, action, answers, onText) {
  const res = await fetch(`/api/servers/${serverId}/run`, {
    method: 'POST',
    headers: { 'x-sbp-token': token, 'content-type': 'application/json' },
    body: JSON.stringify({ action, answers }),
  });
  if (!res.ok) {
    let message = `请求失败 (${res.status})`;
    try {
      message = (await res.json()).error || message;
    } catch {
      // ignore
    }
    throw new Error(message);
  }
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let pending = '';
  let exitCode = null;
  for (;;) {
    const { value, done } = await reader.read();
    pending += decoder.decode(value || new Uint8Array(), { stream: !done });
    const markAt = pending.indexOf(EXIT_MARK);
    if (markAt !== -1) {
      onText(pending.slice(0, markAt));
      exitCode = Number.parseInt(pending.slice(markAt + EXIT_MARK.length), 10);
      pending = '';
    } else if (pending.length > EXIT_MARK.length) {
      // 保留末尾一小段，避免结束标记被拆在两个分片之间。
      const cut = pending.length - EXIT_MARK.length;
      onText(pending.slice(0, cut));
      pending = pending.slice(cut);
    }
    if (done) break;
  }
  if (pending) onText(pending);
  return Number.isNaN(exitCode) || exitCode === null ? -1 : exitCode;
}

export function terminalUrl(serverId, mode, cols, rows) {
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const params = new URLSearchParams({ server: serverId, mode, cols: String(cols), rows: String(rows), token });
  return `${proto}//${window.location.host}/ws/terminal?${params}`;
}

export function stripAnsi(text) {
  return String(text ?? '').replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '');
}

export const PROTOCOL_LABELS = {
  anytls: 'AnyTLS',
  vless_reality: 'VLESS Reality',
  socks5: 'SOCKS5',
  snell: 'Snell',
  trusttunnel: 'TrustTunnel',
  'import-http': '导入链接服务',
  'sing-box': 'sing-box',
};

export const PARAM_PROTOCOLS = new Set(['anytls', 'vless_reality', 'socks5', 'snell', 'trusttunnel']);
