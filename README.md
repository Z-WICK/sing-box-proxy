# sing-box-proxy

这个目录现在按用途分层，根目录只保留入口和说明。

## 直接运行

root 机器上可以直接执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Z-WICK/sing-box-proxy/main/sing-box-proxy-manager.sh | bash
```

如果当前用户不是 root：

```bash
curl -fsSL https://raw.githubusercontent.com/Z-WICK/sing-box-proxy/main/sing-box-proxy-manager.sh | sudo bash
```

如果想先下载再运行：

```bash
curl -fsSL https://raw.githubusercontent.com/Z-WICK/sing-box-proxy/main/sing-box-proxy-manager.sh -o sing-box-proxy-manager.sh
chmod +x sing-box-proxy-manager.sh
sudo ./sing-box-proxy-manager.sh
```

新建 AnyTLS 或 VLESS Reality 时，脚本会先检查 `443`。如果 `443` 已被占用，会默认改用 `8443`；如果当前机器已经有现成服务，脚本会优先保留现有端口。

如果 AnyTLS、VLESS Reality、SOCKS5 或 Snell 由 HAProxy 从公网端口转发到本机内部端口，查看参数和生成的客户端配置会自动使用 HAProxy 前端端口；也可以分别通过 `ANYTLS_PUBLIC_LISTEN_PORT`、`VLESS_REALITY_PUBLIC_LISTEN_PORT`、`SOCKS5_PUBLIC_LISTEN_PORT` 或 `SNELL_PUBLIC_LISTEN_PORT` 显式指定公网端口。内部监听端口只用于服务自身，不会直接展示给客户端。

VLESS Reality 默认启用防偷跑模式。脚本会把 Reality fallback 接到本机内部过滤入口，只允许伪装域名对应的 TLS SNI 被转发，其它 fallback 连接会被拒绝。

SOCKS5 会默认创建独立的 `sing-box-socks5.service`，监听 `0.0.0.0:1080`，如果端口被占用会改用 `1081`。脚本会生成用户名和密码，不创建匿名公开代理。

Snell 会创建独立的 `snell-server.service`，使用 Surge 官方 `snell-server` 二进制，不经过 sing-box。当前支持 Snell v4/v5 和 v6，默认新装 v6；安装或更新时会从 Surge 官方发布页解析所选协议的全部构建并选择最高版本，获取失败时回退到脚本内置版本（当前 v6 回退版本为 `v6.0.0rc2`）。配置文件为 `/etc/snell/config.conf`，监听端口默认为 `2345`，如被占用会建议 `2346`。Snell 菜单提供 v4/v5 到 v6 的保配置升级，迁移时保留监听端口、PSK、DNS、TFO、`egress-interface` 和未知配置项，失败会回滚二进制和配置。Snell v6 的 PSK 必须为 16-255 位；启用 TFO 时仅设置 `net.ipv4.tcp_fastopen`，不修改全局 BBR 或其他网络参数。v6 官方仅提供 `amd64`、`i386`、`aarch64` 构建，不支持 `armv7l`。

TrustTunnel 会使用官方 endpoint 安装脚本下载独立的 `trusttunnel_endpoint`，默认安装到 `/opt/trusttunnel` 并创建 `trusttunnel.service`。配置向导会生成 `vpn.toml`、`hosts.toml`、`credentials.toml` 和 `rules.toml`，默认启用 HTTP/1.1 + HTTP/2；客户端连接地址可以是公网 IP，但 TLS 主机名/SNI 必须是域名；可使用自签证书或已有 PEM 证书。查看参数时会调用 endpoint 原生导出 `tt://?` 深链和 TOML 客户端配置，并按 HAProxy 前端端口展示公网端口；也可以通过 `TRUSTTUNNEL_PUBLIC_LISTEN_PORT` 显式指定公网端口。官方安装来源为 `https://raw.githubusercontent.com/TrustTunnel/TrustTunnel/refs/heads/master/scripts/install.sh`。

AnyTLS、VLESS Reality、SOCKS5 和 Snell 都已拆分为独立模块（`scripts/modules/*.sh`）。主脚本只保留通用能力和菜单分发；后续新增协议可以按模块接入。

`curl | bash` 入口会自动下载主脚本和全部协议模块；某个模块下载失败时会给出提示，并只禁用对应协议功能，不影响其他模块。

当前菜单结构是一级主菜单 + 二级 `Proxy` 菜单 + 三级协议菜单。协议相关功能都收进 `Proxy` 子菜单里，后续新增协议时不会继续挤占主菜单。

## 图形控制台（多服务器管理）

`gui/` 是一个在本机运行的图形控制台，通过 SSH 同时管理多台服务器：

```bash
cd gui
npm install
npm run app        # 构建前端并启动，macOS 会自动在浏览器中打开
```

启动后终端会打印 `http://127.0.0.1:8787/#token=…`，必须用这个带令牌的链接打开。

- **服务器清单**：保存在 `~/.config/sing-box-proxy-gui/servers.json`（权限 0600），只记录主机、端口、用户和私钥路径，不保存密码。
- **添加服务器**：默认从 `~/.ssh/config`（含 `Include`）读取 Host 别名，可勾选多台批量添加；只保存别名，HostName、User、端口、`IdentityAgent` 仍由 ssh 配置决定。也可以手动填写。
- **1Password**：配置了 1Password SSH Agent（`IdentityAgent` 或 `SSH_AUTH_SOCK`）时直接可用，连接时由 1Password 弹窗授权（Touch ID）。SSH 连接复用 10 分钟以减少弹窗，状态刷新最多 3 台并发。需要指定某把密钥时，填写 1Password 导出的 `.pub` 公钥路径。
- **连接方式**：调用本机 `ssh`，沿用 `~/.ssh/config` 和 ssh-agent；只支持密钥登录。可以用 root 登录，也可以用配置了免密 sudo（NOPASSWD）的普通用户。第一次连接时会自动信任主机指纹（`StrictHostKeyChecking=accept-new`），之后指纹变化会被拒绝。
- **脚本同步**：每次操作前会比对哈希，把本地 `scripts/` 和 `tools/` 推送到服务器的 `/root/sing-box-proxy`（同步的是本地工作区的当前内容，包括未提交的改动）。
- **功能**：概览所有服务器的连通性、sing-box 版本和服务状态；查看各协议参数/客户端链接；查看日志；启动/停止/重启服务；在网页终端里运行完整的交互菜单（安装、配置向导、升级、卸载）或打开 root shell。
- **安全**：只监听 `127.0.0.1`，校验 Host 头和 WebSocket Origin，所有接口都需要每次启动时随机生成的令牌。服务器上不会开放新端口，也没有常驻 agent。
- **环境变量**：`SBP_GUI_PORT`（端口）、`SBP_GUI_CONFIG_DIR`（清单目录）、`SBP_GUI_SSH_CONFIG`（使用独立 ssh 配置文件，等同 `ssh -F`）、`SBP_GUI_TOKEN`（固定令牌）。
- **已知限制**：终端连接建立后，窗口尺寸变化不会同步到远端，调整窗口后需要重新连接。

开发模式：`npm run dev:server` 与 `npm run dev:web` 分别启动后端和 Vite，然后打开 `http://127.0.0.1:5173/#token=<后端打印的令牌>`。测试：`npm test`。

控制台依赖主脚本的非交互模式，也可以直接在服务器上调用：

```bash
sudo ./scripts/sing-box-proxy-manager.sh --agent status                 # JSON 状态
sudo ./scripts/sing-box-proxy-manager.sh --agent params socks5          # 协议参数
sudo ./scripts/sing-box-proxy-manager.sh --agent service sing-box-socks5.service restart
sudo ./scripts/sing-box-proxy-manager.sh --agent logs snell-server.service 100
```

`service` / `logs` 只接受本脚本管理的服务（`sing-box*.service`、Snell、TrustTunnel、导入链接服务）。

## 目录

- `sing-box-proxy-manager.sh`：兼容旧习惯的入口脚本，实际实现位于 `scripts/`
- `scripts/sing-box-proxy-manager.sh`：主脚本（菜单与通用能力）
- `scripts/modules/anytls.sh`：AnyTLS 模块
- `scripts/modules/vless_reality.sh`：VLESS + Reality + Vision 模块
- `scripts/modules/socks5.sh`：SOCKS5 模块
- `scripts/modules/snell.sh`：Snell Server 模块，管理 Surge 官方 `snell-server`
- `scripts/modules/trusttunnel.sh`：TrustTunnel endpoint 模块
- `gui/`：本地图形控制台（Node + React），通过 SSH 管理多台服务器
- `tools/`：辅助脚本，例如导入配置的 HTTP 服务
- `docs/reference/`：整理后的上游参考文档
- `data/`：运行时生成的元数据和客户端导入文件，仅远端会使用

## 新增协议模块

主脚本提供了模块注册入口，新增协议时只需要：

1. 在 `scripts/modules/` 新建协议模块文件
2. 在模块里实现 `register_<protocol>_menu_items`，并调用 `register_protocol_menu_item "<协议分类>" "<菜单项>" "<处理函数>"`
3. 在主脚本 `load_protocol_modules()` 里增加一次 `load_protocol_module` 调用
4. 在入口脚本 `sing-box-proxy-manager.sh` 的模块下载列表里增加该模块文件名

## 远端目录建议

远端机器 `/root/sing-box-proxy` 与本地保持同样结构：

- `scripts/`
- `scripts/modules/`
- `tools/`
- `docs/reference/`
- `data/metadata/`
- `data/client-import/`
- `data/client-import-publish/`
- `/etc/sing-box/vless-reality-meta/`：VLESS Reality 客户端导入所需的 Public Key 元数据
- `/etc/sing-box/socks5-meta/`：SOCKS5 客户端回显所需的服务器地址元数据
- `/etc/snell/`：Snell Server 配置与版本记录
- `/opt/trusttunnel/`：TrustTunnel endpoint、配置和客户端导出文件
- `/etc/trusttunnel-meta/`：TrustTunnel 客户端地址和显示名称元数据
- `archive/`：不再直接使用、但先保留的旧文件
