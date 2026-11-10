// 图形化操作目录。每个字段的 key 与脚本里 ask_text / prompt_yes_no 的答案键一一对应；
// 留空的字段不会发送，脚本会沿用现有配置或使用默认值。
// fixed：每次执行都会固定发送的答案（例如跳过“保持现有配置”的询问）。

const KEEP = { value: '', label: '沿用当前设置' };

export const PROTOCOLS = [
  {
    id: 'anytls',
    name: 'AnyTLS',
    needsSingbox: true,
    summary: '基于 TLS 的轻量代理，自动选择 443（被占用时用 8443）并生成密码与自签证书。',
  },
  {
    id: 'vless_reality',
    name: 'VLESS Reality',
    needsSingbox: true,
    summary: 'VLESS + Reality + Vision，借用真实网站的 TLS 握手，默认开启防偷跑。',
  },
  {
    id: 'socks5',
    name: 'SOCKS5',
    needsSingbox: true,
    summary: '带用户名密码认证的 SOCKS5，监听 1080（被占用时用 1081）。',
  },
  {
    id: 'snell',
    name: 'Snell',
    needsSingbox: false,
    summary: 'Surge 官方 snell-server，支持 v4/v5 与 v6，独立于 sing-box 运行。',
  },
  {
    id: 'trusttunnel',
    name: 'TrustTunnel',
    needsSingbox: false,
    summary: '官方 TrustTunnel endpoint，HTTP/1.1 + HTTP/2，支持自签或已有证书。',
  },
];

export const ACTIONS = {
  'singbox.install': {
    title: '安装 sing-box',
    submit: '安装',
    description: '从 GitHub 下载官方发布的 sing-box 二进制到 /usr/local/bin。',
    fields: [{ key: 'singbox_version', label: '版本', type: 'text', placeholder: '留空安装最新版，例如 1.12.0' }],
    fixed: { configure_service: 'n' },
  },
  'singbox.update': {
    title: '更新 sing-box',
    submit: '更新',
    description: '替换 sing-box 二进制，完成后自动重启默认服务。',
    fields: [
      { key: 'singbox_version', label: '目标版本', type: 'text', placeholder: '留空更新到最新版' },
      {
        key: 'reinstall_same',
        label: '版本相同时',
        type: 'select',
        options: [
          { value: 'n', label: '跳过' },
          { value: 'y', label: '仍然重新安装' },
        ],
      },
    ],
    fixed: { create_service: 'n', restart_after_update: 'y' },
  },
  'singbox.uninstall': {
    title: '完整卸载 sing-box',
    submit: '卸载',
    danger: true,
    description: '停止并删除所有 sing-box 服务（AnyTLS、VLESS Reality、SOCKS5 等）。Snell 和 TrustTunnel 不受影响。',
    fields: [
      { key: 'delete_binary', label: '删除 sing-box 二进制', type: 'check', default: true },
      { key: 'delete_configs', label: '删除服务使用的配置文件', type: 'check', default: true },
      { key: 'delete_metadata', label: '删除客户端导入文件和参数元数据', type: 'check', default: true },
      { key: 'delete_backups', label: '删除备份的旧二进制', type: 'check', default: false },
      { key: 'delete_config_dir', label: '删除整个 /etc/sing-box 目录（含证书）', type: 'check', default: false },
      { key: 'confirm_text', label: '输入 UNINSTALL 确认', type: 'text', placeholder: 'UNINSTALL', required: true, mustEqual: 'UNINSTALL' },
    ],
    fixed: { confirm: 'y' },
  },

  'anytls.configure': {
    title: '配置 AnyTLS',
    submit: '应用配置',
    params: 'anytls',
    description:
      'AnyTLS 全部参数自动生成：端口优先 443（被占用改 8443），自签证书，随机密码。已有配置时沿用现有密码、端口和证书路径重新应用。',
    fields: [],
    fixed: { keep_existing: 'n', anytls_reconfigure: 'y', anytls_fix_port_conflict: 'y' },
  },
  'anytls.uninstall': {
    title: '卸载 AnyTLS',
    submit: '卸载',
    danger: true,
    description: '停止并删除 sing-box-anytls.service，同时删除它的配置、自签证书和元数据。',
    fields: [],
    fixed: { confirm: 'y' },
  },

  'vless_reality.configure': {
    title: '配置 VLESS Reality',
    submit: '应用配置',
    params: 'vless_reality',
    description: '端口优先 443（被占用改 8443）。UUID、Short ID 和 Reality 密钥会自动生成，重配时沿用。',
    fields: [
      {
        key: 'reality_server_name',
        label: '伪装域名（SNI）',
        type: 'text',
        placeholder: '例如 www.example.edu',
        requiredWhenNew: true,
        hint: '填一个真实可访问、支持 TLS 1.3 的网站，不要用大型云厂商或 CDN 的域名。重配时留空则沿用当前域名。',
      },
      {
        key: 'reuse_private_key',
        label: 'Reality 密钥',
        type: 'select',
        options: [
          { value: 'y', label: '沿用现有密钥（客户端无需更新）' },
          { value: 'n', label: '重新生成（客户端需要更新）' },
        ],
        onlyWhenInstalled: true,
      },
    ],
    fixed: { keep_existing: 'n' },
  },

  'socks5.configure': {
    title: '配置 SOCKS5',
    submit: '应用配置',
    params: 'socks5',
    description: '监听 0.0.0.0:1080（被占用改 1081），用户名 proxy。',
    warnWhenInstalled: '重新配置会生成新的密码，正在使用的客户端需要更新。',
    fields: [],
    fixed: { keep_existing: 'n' },
  },

  'snell.configure': {
    title: '配置 Snell',
    submit: '应用配置',
    params: 'snell',
    description: '没有官方二进制或版本不匹配时会自动下载。留空的项沿用当前配置，新装时使用推荐值。',
    fields: [
      {
        key: 'snell_version',
        label: '协议版本',
        type: 'select',
        options: [
          { value: '', label: '沿用当前（新装为 v6）' },
          { value: '6', label: 'v6（推荐）' },
          { value: '5', label: 'v5' },
          { value: '4', label: 'v4' },
        ],
      },
      { key: 'snell_port', label: '监听端口', type: 'text', placeholder: '留空沿用当前，新装为 2345', inputMode: 'numeric' },
      { key: 'snell_psk', label: 'PSK', type: 'password', placeholder: '留空沿用当前或自动生成', hint: 'v6 需要 12-255 位，可用字母、数字和 _ . @ : = + -' },
      {
        key: 'snell_mode',
        label: '模式',
        type: 'select',
        when: (v) => v.snell_version !== '4' && v.snell_version !== '5',
        options: [
          KEEP,
          { value: 'default', label: 'default：混淆 + AES（推荐）' },
          { value: 'unshaped', label: 'unshaped：仅 AES，吞吐更高' },
          { value: 'unsafe-raw', label: 'unsafe-raw：明文，仅限安全内网' },
        ],
      },
      {
        key: 'snell_dns_ip_preference',
        label: 'DNS 地址族偏好',
        type: 'select',
        when: (v) => v.snell_version !== '4' && v.snell_version !== '5',
        options: [KEEP, 'default', 'prefer-ipv4', 'prefer-ipv6', 'ipv4-only', 'ipv6-only'].map((o) =>
          typeof o === 'string' ? { value: o, label: o } : o,
        ),
      },
      {
        key: 'snell_obfs',
        label: 'OBFS',
        type: 'select',
        when: (v) => v.snell_version === '4' || v.snell_version === '5',
        options: [KEEP, { value: 'off', label: 'off（推荐）' }, { value: 'tls', label: 'tls' }, { value: 'http', label: 'http' }],
      },
      {
        key: 'snell_obfs_host',
        label: 'OBFS 域名',
        type: 'text',
        placeholder: '默认 icloud.com',
        when: (v) => (v.snell_version === '4' || v.snell_version === '5') && (v.snell_obfs === 'tls' || v.snell_obfs === 'http'),
      },
      {
        key: 'snell_ipv6',
        label: 'IPv6 解析',
        type: 'select',
        when: (v) => v.snell_version === '4' || v.snell_version === '5',
        options: [KEEP, { value: 'y', label: '开启' }, { value: 'n', label: '关闭' }],
      },
      {
        key: 'snell_tfo',
        label: 'TCP Fast Open',
        type: 'select',
        options: [KEEP, { value: 'y', label: '开启' }, { value: 'n', label: '关闭' }],
      },
      { key: 'snell_dns', label: 'DNS', type: 'text', placeholder: '留空沿用当前，多个用英文逗号分隔' },
    ],
    fixed: { keep_existing: 'n', install_binary: 'y' },
  },
  'snell.upgrade_v6': {
    title: '升级到 Snell v6',
    submit: '升级',
    params: 'snell',
    description: '保留监听端口、PSK、DNS 和 TFO，把 v4/v5 配置迁移到 v6。失败会自动回滚二进制和配置。',
    fields: [
      { key: 'snell_psk', label: '新 PSK（仅当现有 PSK 不满足 v6 要求时使用）', type: 'password', placeholder: '留空自动生成' },
    ],
    fixed: { confirm: 'y' },
  },
  'snell.update': {
    title: '切换 / 更新 Snell 服务端',
    submit: '更新',
    params: 'snell',
    description: '重新下载所选协议版本的最新官方构建，配置会迁移到对应版本。',
    fields: [
      {
        key: 'snell_version',
        label: '协议版本',
        type: 'select',
        options: [
          { value: '', label: '沿用当前版本' },
          { value: '6', label: 'v6' },
          { value: '5', label: 'v5' },
          { value: '4', label: 'v4' },
        ],
      },
    ],
    fixed: {},
  },
  'snell.uninstall': {
    title: '卸载 Snell',
    submit: '卸载',
    danger: true,
    description: '停止并删除 snell-server.service。',
    fields: [
      { key: 'delete_binary', label: '删除 snell-server 二进制', type: 'check', default: true },
      { key: 'delete_config_dir', label: '删除 /etc/snell 配置目录', type: 'check', default: false },
    ],
    fixed: { confirm: 'y' },
  },

  'trusttunnel.configure': {
    title: '配置 TrustTunnel',
    submit: '应用配置',
    params: 'trusttunnel',
    description: '未安装 endpoint 时会先通过官方脚本安装。留空的项沿用当前配置或自动生成。',
    fields: [
      { key: 'tt_server', label: '客户端连接地址', type: 'text', placeholder: '留空使用自动识别的公网 IP' },
      { key: 'tt_hostname', label: 'TLS 主机名（SNI）', type: 'text', placeholder: '例如 vpn.example.com', hint: '必须是域名，客户端用它做 TLS 校验。留空沿用当前值。' },
      { key: 'tt_port', label: '监听端口', type: 'text', placeholder: '留空沿用当前，新装为 443', inputMode: 'numeric' },
      { key: 'tt_username', label: '用户名', type: 'text', placeholder: '留空沿用当前' },
      { key: 'tt_password', label: '密码', type: 'password', placeholder: '留空沿用当前或自动生成' },
      { key: 'tt_display_name', label: '客户端显示名称', type: 'text', placeholder: '留空沿用当前' },
      {
        key: 'tt_ipv6',
        label: 'IPv6 路由',
        type: 'select',
        options: [KEEP, { value: 'y', label: '开启' }, { value: 'n', label: '关闭' }],
      },
      {
        key: 'tt_cert_mode',
        label: '证书',
        type: 'select',
        options: [
          { value: '', label: '沿用当前（新装为自签证书）' },
          { value: '1', label: '自签证书' },
          { value: '2', label: '使用服务器上已有的 PEM 证书' },
        ],
      },
      {
        key: 'reuse_cert',
        label: '自签证书',
        type: 'select',
        when: (v) => v.tt_cert_mode !== '2',
        options: [
          { value: 'y', label: '已存在时沿用' },
          { value: 'n', label: '重新生成' },
        ],
      },
      { key: 'tt_cert_path', label: '证书链 PEM 路径', type: 'text', placeholder: '/etc/ssl/fullchain.pem', when: (v) => v.tt_cert_mode === '2', required: true },
      { key: 'tt_key_path', label: '私钥 PEM 路径', type: 'text', placeholder: '/etc/ssl/privkey.pem', when: (v) => v.tt_cert_mode === '2', required: true },
    ],
    fixed: { install_endpoint: 'y', reconfigure: 'y' },
  },
  'trusttunnel.update': {
    title: '更新 TrustTunnel endpoint',
    submit: '更新',
    description: '通过官方安装脚本更新 endpoint，运行中的服务会在更新后自动重启。',
    fields: [],
    fixed: {},
  },
  'trusttunnel.uninstall': {
    title: '卸载 TrustTunnel',
    submit: '卸载',
    danger: true,
    description: '停止并删除 trusttunnel.service。',
    fields: [
      { key: 'delete_files', label: '删除 endpoint 二进制、配置和证书', type: 'check', default: true },
      { key: 'delete_metadata', label: '删除客户端参数元数据', type: 'check', default: true },
    ],
    fixed: { confirm: 'y' },
  },
};

/** 每个协议卡片上的次要操作。 */
export const SECONDARY_ACTIONS = {
  anytls: ['anytls.uninstall'],
  vless_reality: [],
  socks5: [],
  snell: ['snell.upgrade_v6', 'snell.update', 'snell.uninstall'],
  trusttunnel: ['trusttunnel.update', 'trusttunnel.uninstall'],
};

export function initialValues(action) {
  const values = {};
  for (const field of action.fields) {
    if (field.type === 'check') values[field.key] = Boolean(field.default);
    else if (field.type === 'select') values[field.key] = field.options[0].value;
    else values[field.key] = '';
  }
  return values;
}

export function visibleFields(action, values, { installed }) {
  return action.fields.filter((f) => (!f.when || f.when(values)) && (!f.onlyWhenInstalled || installed));
}

/** 校验表单，返回第一个错误（没有错误时返回空字符串）。 */
export function validateForm(action, values, ctx) {
  for (const field of visibleFields(action, values, ctx)) {
    const value = typeof values[field.key] === 'string' ? values[field.key].trim() : values[field.key];
    if ((field.required || (field.requiredWhenNew && !ctx.installed)) && !value) return `请填写「${field.label}」`;
    if (field.mustEqual && value !== field.mustEqual) return `「${field.label}」需要输入 ${field.mustEqual}`;
    if (field.inputMode === 'numeric' && value && !/^\d{1,5}$/.test(value)) return `「${field.label}」必须是数字`;
  }
  return '';
}

/** 把表单值转换成脚本答案：隐藏字段和空值不发送，勾选框转成 y/n。 */
export function buildAnswers(action, values, ctx) {
  const answers = { ...action.fixed };
  for (const field of visibleFields(action, values, ctx)) {
    const value = values[field.key];
    if (field.type === 'check') answers[field.key] = value ? 'y' : 'n';
    else if (typeof value === 'string' && value.trim() !== '') answers[field.key] = value.trim();
  }
  return answers;
}
