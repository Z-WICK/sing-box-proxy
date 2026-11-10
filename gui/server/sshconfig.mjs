import { execFile } from 'node:child_process';
import { readdir, readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, dirname, isAbsolute, join } from 'node:path';

const MAX_INCLUDE_DEPTH = 8;
const ALIAS_RE = /^[A-Za-z0-9_][A-Za-z0-9._:%-]{0,252}$/;

function userConfigPath() {
  return process.env.SBP_GUI_SSH_CONFIG || join(homedir(), '.ssh', 'config');
}

function expandTilde(path) {
  if (path === '~') return homedir();
  if (path.startsWith('~/')) return join(homedir(), path.slice(2));
  return path;
}

/** 拆分 ssh_config 一行的参数，支持双引号。 */
export function splitArgs(text) {
  const out = [];
  const re = /"([^"]*)"|(\S+)/g;
  let m;
  while ((m = re.exec(text)) !== null) out.push(m[1] ?? m[2]);
  return out;
}

function parseLine(line) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('#')) return null;
  const m = trimmed.match(/^([A-Za-z]+)\s*(?:=\s*|\s+)(.*)$/);
  if (!m) return null;
  return { key: m[1].toLowerCase(), args: splitArgs(m[2]) };
}

function isPattern(token) {
  return /[*?!]/.test(token);
}

/**
 * 从 ssh_config 文本中提取可直接连接的 Host 别名（跳过通配符和否定模式）。
 * `Host bisai 1.2.3.4` 这种多名称写法以第一个名称为别名。
 */
export function parseHostAliases(text) {
  const result = [];
  for (const line of text.split(/\r?\n/)) {
    const parsed = parseLine(line);
    if (!parsed || parsed.key !== 'host') continue;
    const names = parsed.args.filter((t) => !isPattern(t) && ALIAS_RE.test(t));
    if (names.length === 0) continue;
    result.push({ alias: names[0], otherNames: names.slice(1) });
  }
  return result;
}

function globToRegExp(glob) {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.');
  return new RegExp(`^${escaped}$`);
}

async function expandInclude(pattern, baseDir) {
  let path = expandTilde(pattern);
  if (!isAbsolute(path)) path = join(baseDir, path);
  const name = basename(path);
  if (!/[*?]/.test(name)) return [path];
  try {
    const re = globToRegExp(name);
    const dir = dirname(path);
    return (await readdir(dir)).filter((f) => re.test(f)).sort().map((f) => join(dir, f));
  } catch {
    return [];
  }
}

/** 读取配置文件及其 Include 的文件，按出现顺序返回别名。 */
export async function readHostAliases(configPath = userConfigPath()) {
  const sshDir = join(homedir(), '.ssh');
  const seen = new Set();
  const aliases = [];

  async function visit(file, depth) {
    if (depth > MAX_INCLUDE_DEPTH || seen.has(file)) return;
    seen.add(file);
    let text;
    try {
      text = await readFile(file, 'utf8');
    } catch {
      return;
    }
    for (const line of text.split(/\r?\n/)) {
      const parsed = parseLine(line);
      if (!parsed) continue;
      if (parsed.key === 'include') {
        for (const pattern of parsed.args) {
          for (const inc of await expandInclude(pattern, sshDir)) await visit(inc, depth + 1);
        }
      } else if (parsed.key === 'host') {
        aliases.push(...parseHostAliases(line));
      }
    }
  }

  await visit(configPath, 0);
  const unique = new Map();
  for (const entry of aliases) if (!unique.has(entry.alias)) unique.set(entry.alias, entry);
  return [...unique.values()];
}

/** 解析 `ssh -G` 输出。 */
export function parseSshG(output) {
  const values = {};
  for (const line of output.split('\n')) {
    const idx = line.indexOf(' ');
    if (idx <= 0) continue;
    const key = line.slice(0, idx).toLowerCase();
    const value = line.slice(idx + 1).trim();
    if (key === 'identityfile') (values.identityfile ||= []).push(value);
    else values[key] = value;
  }
  return values;
}

export function detectAgent(identityAgent, authSock = process.env.SSH_AUTH_SOCK || '') {
  const agent = identityAgent && identityAgent.toLowerCase() !== 'ssh_auth_sock' ? identityAgent : authSock;
  if (!agent || agent.toLowerCase() === 'none') return 'none';
  if (/1password/i.test(agent)) return '1password';
  return 'agent';
}

function sshG(alias) {
  const args = [];
  if (process.env.SBP_GUI_SSH_CONFIG) args.push('-F', process.env.SBP_GUI_SSH_CONFIG);
  args.push('-G', '--', alias);
  return new Promise((resolve) => {
    execFile('ssh', args, { timeout: 5000 }, (err, stdout) => resolve(err ? null : stdout));
  });
}

/** 列出 ~/.ssh/config 中的主机及其生效配置（只在本地解析，不会连接服务器）。 */
export async function listSshHosts() {
  const aliases = await readHostAliases();
  return Promise.all(
    aliases.map(async ({ alias, otherNames }) => {
      const out = await sshG(alias);
      const g = out ? parseSshG(out) : {};
      return {
        alias,
        otherNames,
        hostname: g.hostname || alias,
        user: g.user || null,
        port: g.port ? Number(g.port) : null,
        agent: detectAgent(g.identityagent),
        identitiesOnly: g.identitiesonly === 'yes',
      };
    }),
  );
}
