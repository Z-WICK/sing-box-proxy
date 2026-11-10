import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, statSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';
import { gzipSync } from 'node:zlib';

export const REMOTE_DIR = '/root/sing-box-proxy';
export const REMOTE_SCRIPT = `${REMOTE_DIR}/scripts/sing-box-proxy-manager.sh`;
const REMOTE_HASH_FILE = `${REMOTE_DIR}/.gui-sync-hash`;
const BUNDLE_DIRS = ['scripts', 'tools'];
const SKIP_NAMES = new Set(['__pycache__', '.DS_Store']);

/** POSIX 单引号转义：结果可以安全地拼进远端 shell 命令。 */
export function shq(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

export class SshError extends Error {
  constructor(message, { code = null, stderr = '' } = {}) {
    super(message);
    this.name = 'SshError';
    this.exitCode = code;
    this.stderr = stderr;
  }
}

function controlDir() {
  // unix socket 路径有长度限制，macOS 的 $TMPDIR 太长，因此固定放在 /tmp 下。
  const uid = typeof process.getuid === 'function' ? process.getuid() : 'user';
  const dir = `/tmp/sbp-gui-${uid}`;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const st = statSync(dir);
  if (typeof process.getuid === 'function' && (st.uid !== process.getuid() || (st.mode & 0o077) !== 0)) {
    throw new Error(`SSH 复用目录 ${dir} 的属主或权限不安全，请删除后重试`);
  }
  return dir;
}

export function sshArgs(server, { tty = false } = {}) {
  const args = [];
  // 可选：使用独立的 ssh 配置文件（替代 ~/.ssh/config）。
  if (process.env.SBP_GUI_SSH_CONFIG) args.push('-F', process.env.SBP_GUI_SSH_CONFIG);
  args.push(
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=10',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'ServerAliveInterval=15',
    '-o', 'ControlMaster=auto',
    '-o', `ControlPath=${controlDir()}/%C`,
    // 复用连接保持 10 分钟：使用 1Password 等需要确认的 SSH Agent 时，可以减少授权弹窗。
    '-o', 'ControlPersist=600',
  );
  if (tty) args.push('-tt');
  if (server.port) args.push('-p', String(server.port));
  if (server.user) args.push('-l', server.user);
  if (server.identityFile) args.push('-i', server.identityFile, '-o', 'IdentitiesOnly=yes');
  args.push('--', server.host);
  return args;
}

/**
 * 生成在远端以 root 身份执行 command 的命令。
 * 远端登录 shell 可能是 bash/zsh/fish，统一包一层 sh -c。
 * 非 root 用户使用 sudo -n（要求免密 sudo，不会卡在密码提示上）。
 */
export function remoteAsRoot(command, { prelude = '' } = {}) {
  const script = `${prelude}if [ "$(id -u)" -eq 0 ]; then exec ${command}; else exec sudo -n ${command}; fi`;
  return `sh -c ${shq(script)}`;
}

export function agentCommand(args) {
  return remoteAsRoot(['bash', REMOTE_SCRIPT, '--agent', ...args].map(shq).join(' '));
}

export function explainSshFailure(code, stderr) {
  const text = stderr.trim();
  if (/a password is required|a terminal is required|no tty present/i.test(text)) {
    return '当前 SSH 用户不是 root，且没有免密 sudo。请使用 root 登录，或为该用户配置 NOPASSWD sudo。';
  }
  if (/agent refused operation|sign_and_send_pubkey: signing failed|communication with agent failed|error fetching identities/i.test(text)) {
    return 'SSH Agent 拒绝签名或无法连接。使用 1Password 时请确认 1Password 已解锁、设置中已开启 SSH Agent，并在弹窗中授权。';
  }
  if (/Permission denied \(publickey/i.test(text)) {
    return 'SSH 公钥认证失败。请确认密钥已在 ssh-agent / 1Password 中并已加入服务器的 authorized_keys；若服务器配置了 IdentityFile，使用 1Password 时应指向对应的 .pub 公钥。';
  }
  if (/Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED/i.test(text)) {
    return '主机密钥校验失败（服务器指纹与 known_hosts 不一致）。请手动核实后更新 ~/.ssh/known_hosts。';
  }
  if (code === 255) {
    return `SSH 连接失败：${text.split('\n').pop() || '未知错误'}`;
  }
  const lastErr = text.split('\n').filter(Boolean).pop();
  return lastErr ? lastErr.replace(/^\[ERR \]\s*/, '') : `远端命令退出码 ${code}`;
}

export function runSsh(server, remoteCommand, { input = null, timeoutMs = 120_000 } = {}) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawn('ssh', [...sshArgs(server), remoteCommand], { stdio: ['pipe', 'pipe', 'pipe'] });
    } catch (err) {
      reject(err);
      return;
    }
    const out = [];
    const errOut = [];
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
    }, timeoutMs);

    child.stdout.on('data', (chunk) => out.push(chunk));
    child.stderr.on('data', (chunk) => errOut.push(chunk));
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err.code === 'ENOENT' ? new Error('本机未找到 ssh 命令') : err);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      const stdout = Buffer.concat(out).toString('utf8');
      const stderr = Buffer.concat(errOut).toString('utf8');
      if (timedOut) {
        reject(new SshError(`远端命令超时（${Math.round(timeoutMs / 1000)} 秒）`, { code, stderr }));
        return;
      }
      resolve({ code, stdout, stderr });
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input ?? undefined);
  });
}

export async function runAgent(server, args, options) {
  const result = await runSsh(server, agentCommand(args), options);
  if (result.code !== 0) {
    throw new SshError(explainSshFailure(result.code, result.stderr), result);
  }
  return result;
}

// ---------------------------------------------------------------------------
// 脚本同步：把本地 scripts/ 与 tools/ 打包成 tar.gz，经 SSH 解压到远端。
// 不依赖本机 tar（避免 macOS bsdtar 写入扩展属性），自己生成 ustar。
// ---------------------------------------------------------------------------

async function collectFiles(repoRoot) {
  const files = [];
  async function walk(dir) {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (SKIP_NAMES.has(entry.name) || entry.name.endsWith('.pyc')) continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
      } else if (entry.isFile()) {
        files.push({ path: relative(repoRoot, full).split(sep).join('/'), content: await readFile(full) });
      }
    }
  }
  for (const dir of BUNDLE_DIRS) await walk(join(repoRoot, dir));
  files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return files;
}

function octal(value, width) {
  return `${value.toString(8).padStart(width - 1, '0')}\0`;
}

export function tarHeader(path, size, mode, mtime) {
  if (Buffer.byteLength(path) > 99) throw new Error(`路径过长，无法打包: ${path}`);
  const header = Buffer.alloc(512, 0);
  header.write(path, 0, 100, 'utf8');
  header.write(octal(mode, 8), 100, 8, 'ascii');
  header.write(octal(0, 8), 108, 8, 'ascii');
  header.write(octal(0, 8), 116, 8, 'ascii');
  header.write(octal(size, 12), 124, 12, 'ascii');
  header.write(octal(mtime, 12), 136, 12, 'ascii');
  header.write('        ', 148, 8, 'ascii');
  header.write('0', 156, 1, 'ascii');
  header.write('ustar\0', 257, 6, 'ascii');
  header.write('00', 263, 2, 'ascii');
  header.write('root', 265, 32, 'ascii');
  header.write('root', 297, 32, 'ascii');
  let sum = 0;
  for (const byte of header) sum += byte;
  header.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148, 8, 'ascii');
  return header;
}

export function buildTar(files, mtime = Math.floor(Date.now() / 1000)) {
  const parts = [];
  for (const file of files) {
    const mode = /\.(sh|py)$/.test(file.path) ? 0o755 : 0o644;
    parts.push(tarHeader(file.path, file.content.length, mode, mtime), file.content);
    const pad = (512 - (file.content.length % 512)) % 512;
    if (pad) parts.push(Buffer.alloc(pad, 0));
  }
  parts.push(Buffer.alloc(1024, 0));
  return Buffer.concat(parts);
}

export function hashFiles(files) {
  const hash = createHash('sha256');
  for (const file of files) {
    hash.update(file.path).update('\0').update(file.content).update('\0');
  }
  return hash.digest('hex');
}

export async function buildBundle(repoRoot) {
  const files = await collectFiles(repoRoot);
  if (!files.some((f) => f.path === 'scripts/sing-box-proxy-manager.sh')) {
    throw new Error(`未在 ${repoRoot} 找到 scripts/sing-box-proxy-manager.sh`);
  }
  return { hash: hashFiles(files), archive: gzipSync(buildTar(files)), fileCount: files.length };
}

export class ScriptSyncer {
  constructor(repoRoot) {
    this.repoRoot = repoRoot;
    this.syncedHash = new Map();
    this.inflight = new Map();
  }

  /** 确保远端脚本与本地一致。返回 { synced: boolean, hash }。 */
  ensure(server, { force = false } = {}) {
    const key = server.id;
    if (this.inflight.has(key)) return this.inflight.get(key);
    const task = this.#ensure(server, force).finally(() => this.inflight.delete(key));
    this.inflight.set(key, task);
    return task;
  }

  forget(serverId) {
    this.syncedHash.delete(serverId);
  }

  async #ensure(server, force) {
    const bundle = await buildBundle(this.repoRoot);
    if (!force && this.syncedHash.get(server.id) === bundle.hash) {
      return { synced: false, hash: bundle.hash };
    }

    if (!force) {
      // 首次连接可能需要等待 1Password / Touch ID 授权，超时放宽。
      const check = await runSsh(server, remoteAsRoot(`cat ${shq(REMOTE_HASH_FILE)}`), { timeoutMs: 120_000 });
      if (check.code === 255 || /sudo:/.test(check.stderr)) {
        throw new SshError(explainSshFailure(check.code, check.stderr), check);
      }
      if (check.code === 0 && check.stdout.trim() === bundle.hash) {
        this.syncedHash.set(server.id, bundle.hash);
        return { synced: false, hash: bundle.hash };
      }
    }

    const install = [
      'set -e',
      `d=${shq(REMOTE_DIR)}`,
      'mkdir -p "$d"',
      'tar -xzf - -C "$d" --no-same-owner',
      `printf %s ${shq(bundle.hash)} > ${shq(REMOTE_HASH_FILE)}`,
    ].join('; ');
    const result = await runSsh(server, remoteAsRoot(`sh -c ${shq(install)}`), {
      input: bundle.archive,
      timeoutMs: 60_000,
    });
    if (result.code !== 0) {
      throw new SshError(`同步脚本失败：${explainSshFailure(result.code, result.stderr)}`, result);
    }
    this.syncedHash.set(server.id, bundle.hash);
    return { synced: true, hash: bundle.hash };
  }
}
