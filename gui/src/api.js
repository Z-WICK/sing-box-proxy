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
