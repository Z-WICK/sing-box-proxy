#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { ScriptSyncer, SshError, agentCommand, explainSshFailure, runAgent, streamSsh } from './ssh.mjs';
import { listSshHosts } from './sshconfig.mjs';
import { ServerStore } from './store.mjs';
import { TERMINAL_MODES, attachTerminal } from './terminal.mjs';
import {
  isValidRunAction,
  validateAnswers,
  isValidProtocol,
  isValidServiceAction,
  isValidUnit,
  parseLogLines,
  validateServer,
} from './validate.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const GUI_ROOT = resolve(HERE, '..');
const REPO_ROOT = resolve(GUI_ROOT, '..');
const DIST_DIR = join(GUI_ROOT, 'dist');
const MAX_BODY = 64 * 1024;
export const EXIT_MARK = '\u0000SBP_EXIT:';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.json': 'application/json; charset=utf-8',
};

function parseArgs(argv) {
  const opts = { port: Number(process.env.SBP_GUI_PORT) || 8787, open: process.platform === 'darwin' };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--port') opts.port = Number(argv[++i]);
    else if (argv[i] === '--no-open') opts.open = false;
    else if (argv[i] === '--open') opts.open = true;
  }
  if (!Number.isInteger(opts.port) || opts.port < 1 || opts.port > 65535) {
    throw new Error('端口不合法');
  }
  return opts;
}

// ---------------------------------------------------------------------------
// 安全：控制台能以 root 在服务器上执行命令，必须防止其它网页借浏览器访问本地端口。
// 1. 只监听 127.0.0.1；2. 校验 Host 头，阻止 DNS rebinding；
// 3. 每次启动生成随机令牌，所有 API 和 WebSocket 都必须携带；4. WebSocket 校验 Origin。
// ---------------------------------------------------------------------------

export function isLoopbackHost(hostHeader) {
  if (!hostHeader) return false;
  const host = hostHeader.replace(/:\d+$/, '').toLowerCase();
  return host === '127.0.0.1' || host === 'localhost' || host === '[::1]';
}

export function isAllowedOrigin(origin) {
  if (!origin) return false;
  try {
    const url = new URL(origin);
    return url.protocol === 'http:' && isLoopbackHost(url.host);
  } catch {
    return false;
  }
}

export function tokenMatches(expected, provided) {
  if (typeof provided !== 'string') return false;
  const a = Buffer.from(expected);
  const b = Buffer.from(provided);
  return a.length === b.length && timingSafeEqual(a, b);
}

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(payload);
}

function readJson(req) {
  return new Promise((resolveBody, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(Object.assign(new Error('请求体过大'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (chunks.length === 0) return resolveBody({});
      try {
        resolveBody(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(Object.assign(new Error('请求体不是合法 JSON'), { status: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function serveStatic(req, res) {
  if (!existsSync(DIST_DIR)) {
    res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('前端尚未构建。请在 gui/ 目录执行 npm run build，或使用 npm run app。\n');
    return;
  }
  const urlPath = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  let filePath = normalize(join(DIST_DIR, urlPath));
  if (!filePath.startsWith(DIST_DIR + sep) && filePath !== DIST_DIR) {
    res.writeHead(403).end();
    return;
  }
  if (!existsSync(filePath) || statSync(filePath).isDirectory()) {
    filePath = join(DIST_DIR, 'index.html');
  }
  res.writeHead(200, {
    'content-type': MIME[extname(filePath)] || 'application/octet-stream',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  });
  createReadStream(filePath).pipe(res);
}

function errorStatus(err) {
  if (err.status) return err.status;
  if (err instanceof SshError) return 502;
  return 500;
}

export function createApp({ store, syncer, token, sshHosts = listSshHosts, stream = streamSsh }) {
  const running = new Set();

  async function withServer(id, res, fn) {
    const server = store.get(id);
    if (!server) {
      sendJson(res, 404, { error: '服务器不存在' });
      return;
    }
    await fn(server);
  }

  const routes = [
    ['GET', /^\/api\/servers$/, async (_req, res) => {
      sendJson(res, 200, { servers: store.list() });
    }],
    ['GET', /^\/api\/ssh-hosts$/, async (_req, res) => {
      sendJson(res, 200, { hosts: await sshHosts() });
    }],
    ['POST', /^\/api\/servers\/batch$/, async (req, res) => {
      const body = await readJson(req);
      if (!Array.isArray(body.servers) || body.servers.length === 0 || body.servers.length > 100) {
        return sendJson(res, 400, { error: 'servers 必须是 1-100 项的数组' });
      }
      const values = [];
      for (const item of body.servers) {
        const parsed = validateServer(item);
        if (!parsed.ok) return sendJson(res, 400, { error: `${item?.name ?? '?'}：${parsed.error}` });
        values.push(parsed.value);
      }
      const created = [];
      for (const value of values) created.push(await store.add(value));
      sendJson(res, 201, { servers: created });
    }],
    ['POST', /^\/api\/servers$/, async (req, res) => {
      const parsed = validateServer(await readJson(req));
      if (!parsed.ok) return sendJson(res, 400, { error: parsed.error });
      sendJson(res, 201, { server: await store.add(parsed.value) });
    }],
    ['PUT', /^\/api\/servers\/([\w-]+)$/, async (req, res, [id]) => {
      const parsed = validateServer(await readJson(req));
      if (!parsed.ok) return sendJson(res, 400, { error: parsed.error });
      const server = await store.update(id, parsed.value);
      if (!server) return sendJson(res, 404, { error: '服务器不存在' });
      syncer.forget(id);
      sendJson(res, 200, { server });
    }],
    ['DELETE', /^\/api\/servers\/([\w-]+)$/, async (_req, res, [id]) => {
      if (!(await store.remove(id))) return sendJson(res, 404, { error: '服务器不存在' });
      syncer.forget(id);
      sendJson(res, 200, { ok: true });
    }],
    ['POST', /^\/api\/servers\/([\w-]+)\/sync$/, async (_req, res, [id]) => {
      await withServer(id, res, async (server) => {
        sendJson(res, 200, await syncer.ensure(server, { force: true }));
      });
    }],
    ['GET', /^\/api\/servers\/([\w-]+)\/status$/, async (_req, res, [id]) => {
      await withServer(id, res, async (server) => {
        const sync = await syncer.ensure(server);
        const { stdout } = await runAgent(server, ['status'], { timeoutMs: 120_000 });
        let status;
        try {
          status = JSON.parse(stdout);
        } catch {
          throw new SshError(`无法解析远端状态输出：${stdout.slice(0, 200)}`);
        }
        sendJson(res, 200, { status, synced: sync.synced, checkedAt: new Date().toISOString() });
      });
    }],
    ['GET', /^\/api\/servers\/([\w-]+)\/params\/([\w-]+)$/, async (req, res, [id, protocol], query) => {
      if (!isValidProtocol(protocol)) return sendJson(res, 400, { error: '未知协议' });
      const unit = query.get('unit');
      if (unit && !isValidUnit(unit)) return sendJson(res, 400, { error: '服务名不合法' });
      await withServer(id, res, async (server) => {
        await syncer.ensure(server);
        const { stdout, stderr } = await runAgent(server, ['params', protocol, ...(unit ? [unit] : [])]);
        sendJson(res, 200, { output: stdout, log: stderr });
      });
    }],
    ['POST', /^\/api\/servers\/([\w-]+)\/service$/, async (req, res, [id]) => {
      const body = await readJson(req);
      if (!isValidUnit(body.unit)) return sendJson(res, 400, { error: '服务名不合法' });
      if (!isValidServiceAction(body.action)) return sendJson(res, 400, { error: '不支持的操作' });
      await withServer(id, res, async (server) => {
        await syncer.ensure(server);
        const { stdout, stderr } = await runAgent(server, ['service', body.unit, body.action]);
        sendJson(res, 200, { output: `${stdout}${stderr}`.trim() });
      });
    }],
    ['POST', /^\/api\/servers\/([\w-]+)\/run$/, async (req, res, [id]) => {
      const body = await readJson(req);
      if (!isValidRunAction(body.action)) return sendJson(res, 400, { error: '不支持的操作' });
      const answers = validateAnswers(body.answers);
      if (!answers.ok) return sendJson(res, 400, { error: answers.error });
      await withServer(id, res, async (server) => {
        if (running.has(id)) return sendJson(res, 409, { error: '这台服务器上已有操作正在执行，请等它完成。' });
        running.add(id);
        try {
          await syncer.ensure(server);
          res.writeHead(200, {
            'content-type': 'text/plain; charset=utf-8',
            'cache-control': 'no-store',
            'x-content-type-options': 'nosniff',
          });
          const input = answers.value.map(([k, v]) => `${k}=${v}\n`).join('');
          let result;
          try {
            result = await stream(server, agentCommand(['run', body.action, '--answers-stdin']), {
              input,
              onData: (chunk) => res.write(chunk),
            });
          } catch (err) {
            res.write(`\n[ERR ] ${err.message}\n`);
            result = { code: -1, stderr: '' };
          }
          if (result.code === 255) res.write(`\n[ERR ] ${explainSshFailure(255, result.stderr)}\n`);
          res.end(`\n${EXIT_MARK}${result.code}\n`);
        } finally {
          running.delete(id);
        }
      });
    }],
    ['GET', /^\/api\/servers\/([\w-]+)\/logs$/, async (req, res, [id], query) => {
      const unit = query.get('unit');
      const lines = parseLogLines(query.get('lines'));
      if (!isValidUnit(unit)) return sendJson(res, 400, { error: '服务名不合法' });
      if (lines === null) return sendJson(res, 400, { error: '行数必须为 1-5000' });
      await withServer(id, res, async (server) => {
        await syncer.ensure(server);
        const { stdout } = await runAgent(server, ['logs', unit, String(lines)]);
        sendJson(res, 200, { output: stdout });
      });
    }],
  ];

  async function handle(req, res) {
    if (!isLoopbackHost(req.headers.host)) {
      res.writeHead(421, { 'content-type': 'text/plain; charset=utf-8' }).end('仅允许通过 127.0.0.1 或 localhost 访问\n');
      return;
    }
    const url = new URL(req.url, 'http://localhost');
    if (!url.pathname.startsWith('/api/')) {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        res.writeHead(405).end();
        return;
      }
      serveStatic(req, res);
      return;
    }

    if (!tokenMatches(token, req.headers['x-sbp-token'])) {
      sendJson(res, 401, { error: '访问令牌无效，请使用启动时打印的链接打开控制台' });
      return;
    }

    for (const [method, pattern, handler] of routes) {
      if (req.method !== method) continue;
      const match = url.pathname.match(pattern);
      if (!match) continue;
      try {
        await handler(req, res, match.slice(1), url.searchParams);
      } catch (err) {
        if (!res.headersSent) sendJson(res, errorStatus(err), { error: err.message });
      }
      return;
    }
    sendJson(res, 404, { error: '接口不存在' });
  }

  const wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 });

  function handleUpgrade(req, socket, head) {
    const url = new URL(req.url, 'http://localhost');
    const reject = (code, text) => {
      socket.write(`HTTP/1.1 ${code} ${text}\r\nConnection: close\r\n\r\n`);
      socket.destroy();
    };
    if (url.pathname !== '/ws/terminal') return reject(404, 'Not Found');
    if (!isLoopbackHost(req.headers.host)) return reject(421, 'Misdirected Request');
    if (!isAllowedOrigin(req.headers.origin)) return reject(403, 'Forbidden');
    if (!tokenMatches(token, url.searchParams.get('token'))) return reject(401, 'Unauthorized');

    const server = store.get(url.searchParams.get('server') || '');
    if (!server) return reject(404, 'Not Found');
    const mode = url.searchParams.get('mode') || 'menu';
    if (!TERMINAL_MODES.includes(mode)) return reject(400, 'Bad Request');

    wss.handleUpgrade(req, socket, head, async (ws) => {
      try {
        if (mode === 'menu') {
          ws.send(Buffer.from('正在同步脚本…\r\n'), { binary: true });
          const { synced } = await syncer.ensure(server);
          if (synced) ws.send(Buffer.from('脚本已更新到服务器。\r\n'), { binary: true });
        }
        if (ws.readyState !== ws.OPEN) return;
        attachTerminal(ws, server, {
          mode,
          cols: url.searchParams.get('cols'),
          rows: url.searchParams.get('rows'),
        });
      } catch (err) {
        if (ws.readyState === ws.OPEN) {
          ws.send(Buffer.from(`\r\n[错误] ${err.message}\r\n`), { binary: true });
          ws.close(1011, 'sync failed');
        }
      }
    });
  }

  return { handle, handleUpgrade };
}

function openBrowser(url) {
  const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'explorer' : 'xdg-open';
  try {
    spawn(cmd, [url], { stdio: 'ignore', detached: true }).on('error', () => {}).unref();
  } catch {
    // 打不开浏览器时用户可手动复制链接
  }
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const token = process.env.SBP_GUI_TOKEN || randomBytes(24).toString('hex');
  const store = await new ServerStore().load();
  const syncer = new ScriptSyncer(REPO_ROOT);
  const app = createApp({ store, syncer, token });

  const httpServer = createServer((req, res) => {
    app.handle(req, res).catch((err) => {
      if (!res.headersSent) sendJson(res, 500, { error: err.message });
    });
  });
  httpServer.on('upgrade', app.handleUpgrade);

  httpServer.listen(opts.port, '127.0.0.1', () => {
    const url = `http://127.0.0.1:${opts.port}/#token=${token}`;
    console.log('sing-box-proxy 图形控制台已启动');
    console.log(`  地址: ${url}`);
    console.log(`  服务器清单: ${store.file}`);
    console.log('  按 Ctrl+C 退出');
    if (opts.open) openBrowser(url);
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
