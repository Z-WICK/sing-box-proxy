// 把脚本「查看参数」的纯文本输出解析成结构化数据。
// 输出格式约定（见 scripts/modules/*.sh 的 show_*_parameters_for_service）：
//   小节标题：顶格、以 ":" 或 "：" 结尾，例如 "Surge:"、"SOCKS5 参数："
//   键值行：  两格缩进 + "键  : 值"
//   独立值：  两格缩进 + 值（URI、Surge 代理行、测试命令等）
//   其它顶格行：提示信息
// 解析不出结构时由界面回退为原始文本。

const SECTION_RE = /^(\S.*?)\s*[:：]\s*$/;
const KV_RE = /^\s{2,}([^\s:：][^:：]{0,24}?)\s*[:：] (.*)$/;
const ITEM_RE = /^\s{2,}(\S.*)$/;

export function parseParams(text) {
  const sections = [];
  const notes = [];
  let current = null;

  for (const raw of String(text ?? '').split(/\r?\n/)) {
    const line = raw.replace(/\s+$/, '');
    if (!line.trim()) continue;
    let m;
    if (!/^\s/.test(line) && (m = line.match(SECTION_RE))) {
      current = { title: m[1].trim(), items: [] };
      sections.push(current);
      continue;
    }
    if (current && (m = line.match(KV_RE))) {
      current.items.push({ key: m[1].trim(), value: m[2].trim() });
      continue;
    }
    if (current && (m = line.match(ITEM_RE))) {
      current.items.push({ key: null, value: m[1] });
      continue;
    }
    notes.push(line.trim());
  }

  return { sections: sections.filter((s) => s.items.length > 0), notes };
}

export function isSecretKey(key) {
  return Boolean(key) && /密码|psk|password|token|uuid/i.test(key);
}

export function isLink(value) {
  return /^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(value);
}

export function isPath(value) {
  return /^\/[^\s]*$/.test(value);
}

/** 代码样式的长值：链接、代理行、命令等，适合放在代码块里整行复制。 */
export function isCodeLike(item) {
  if (isLink(item.value)) return true;
  if (!item.key) return true;
  return /代理参数|URI|深链/i.test(item.key);
}

/** 找出最适合扫码导入的分享链接（协议 URI 优先，排除 http(s) 文件链接）。 */
export function findShareLink(parsed) {
  const candidates = [];
  for (const section of parsed.sections) {
    for (const item of section.items) {
      if (!isLink(item.value) || /^https?:/i.test(item.value)) continue;
      const score = /URI|深链/i.test(`${section.title} ${item.key ?? ''}`) ? 2 : 1;
      candidates.push({ score, value: item.value, label: item.key || section.title });
    }
  }
  candidates.sort((a, b) => b.score - a.score);
  return candidates[0] || null;
}

/** 从基础参数里取「服务器:端口」作为摘要。 */
export function findEndpoint(parsed) {
  const base = parsed.sections[0];
  if (!base) return null;
  const get = (re) => base.items.find((i) => i.key && re.test(i.key))?.value;
  const server = get(/^服务器$/);
  const port = get(/^端口$/);
  if (!server) return null;
  const host = server.includes(':') && !server.startsWith('[') ? `[${server}]` : server;
  return port ? `${host}:${port}` : host;
}

export function noteTone(note) {
  return /警告|安全提示|请勿外传|暴露/.test(note) ? 'warn' : 'info';
}

/** 标签页名称：去掉多余的「配置」「参数」等后缀，保持简短。 */
export function sectionLabel(title, index) {
  if (index === 0) return '参数';
  return title.replace(/\s*(TOML )?客户端配置$/, ' 配置').replace(/：$/, '');
}
