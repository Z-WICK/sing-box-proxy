import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';

const HOST_RE = /^[A-Za-z0-9_][A-Za-z0-9._:%-]{0,252}$/;
const USER_RE = /^[A-Za-z_][A-Za-z0-9_.-]{0,31}$/;
const UNIT_RE = /^[A-Za-z0-9_.@-]+\.service$/;

export const PROTOCOLS = ['anytls', 'vless_reality', 'socks5', 'snell', 'trusttunnel'];
export const SERVICE_ACTIONS = ['start', 'stop', 'restart', 'enable', 'disable'];

function fail(error) {
  return { ok: false, error };
}

function expandHome(path) {
  if (path === '~') return homedir();
  if (path.startsWith('~/')) return join(homedir(), path.slice(2));
  return path;
}

/**
 * 校验并规范化服务器条目。所有字段最终都会作为 ssh 参数使用，
 * 因此必须拒绝以 "-" 开头或包含空白/控制字符的值，防止选项注入。
 */
export function validateServer(input) {
  if (!input || typeof input !== 'object') return fail('请求体必须是对象');

  const name = String(input.name ?? '').trim();
  if (!name || name.length > 64 || /[\u0000-\u001f]/.test(name)) {
    return fail('名称必须为 1-64 个字符');
  }

  const host = String(input.host ?? '').trim();
  if (!HOST_RE.test(host)) {
    return fail('主机只能包含字母、数字和 . _ : % -，且不能以 - 开头');
  }

  let port = null;
  if (input.port !== undefined && input.port !== null && String(input.port).trim() !== '') {
    port = Number(input.port);
    if (!Number.isInteger(port) || port < 1 || port > 65535) return fail('端口必须是 1-65535 的整数');
  }

  let user = null;
  if (input.user !== undefined && input.user !== null && String(input.user).trim() !== '') {
    user = String(input.user).trim();
    if (!USER_RE.test(user)) return fail('用户名不合法');
  }

  let identityFile = null;
  if (input.identityFile !== undefined && input.identityFile !== null && String(input.identityFile).trim() !== '') {
    identityFile = expandHome(String(input.identityFile).trim());
    if (!isAbsolute(identityFile) || /[\u0000-\u001f]/.test(identityFile)) {
      return fail('私钥路径必须是绝对路径或以 ~/ 开头');
    }
  }

  return { ok: true, value: { name, host, port, user, identityFile } };
}

export function isValidUnit(unit) {
  return typeof unit === 'string' && UNIT_RE.test(unit) && !unit.startsWith('-');
}

export function isValidProtocol(protocol) {
  return PROTOCOLS.includes(protocol);
}

export function isValidServiceAction(action) {
  return SERVICE_ACTIONS.includes(action);
}

export function parseLogLines(value) {
  if (value === undefined || value === null || value === '') return 200;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 5000) return null;
  return n;
}

export const RUN_ACTIONS = [
  'singbox.install',
  'singbox.update',
  'singbox.uninstall',
  'anytls.configure',
  'anytls.uninstall',
  'vless_reality.configure',
  'socks5.configure',
  'snell.configure',
  'snell.upgrade_v6',
  'snell.update',
  'snell.uninstall',
  'trusttunnel.configure',
  'trusttunnel.update',
  'trusttunnel.uninstall',
];

export function isValidRunAction(action) {
  return RUN_ACTIONS.includes(action);
}

/**
 * 校验操作答案：键只能是小写字母、数字和下划线；值为单行字符串。
 * 答案经 stdin 以 key=value 逐行传给远端脚本，因此值里不能有换行或 NUL。
 */
export function validateAnswers(input) {
  if (input === undefined || input === null) return { ok: true, value: [] };
  if (typeof input !== 'object' || Array.isArray(input)) return { ok: false, error: 'answers 必须是对象' };
  const entries = Object.entries(input);
  if (entries.length > 40) return { ok: false, error: '答案过多' };
  const value = [];
  for (const [key, raw] of entries) {
    if (!/^[a-z0-9_]{1,40}$/.test(key)) return { ok: false, error: `答案键不合法: ${key}` };
    if (raw === undefined || raw === null || raw === '') continue;
    const text = String(raw);
    if (text.length > 1024 || /[\r\n\u0000]/.test(text)) return { ok: false, error: `答案 ${key} 不能包含换行，且不能超过 1024 个字符` };
    value.push([key, text]);
  }
  return { ok: true, value };
}
