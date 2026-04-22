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

新建 AnyTLS 时，脚本会先检查 `443`。如果 `443` 已被占用，会默认改用 `8443`；如果当前机器已经有现成的 AnyTLS 服务，脚本会优先保留现有端口。

VLESS Reality 已拆分为独立模块（`scripts/modules/vless_reality.sh`）。`curl | bash` 入口会自动下载该模块；如果模块下载失败，脚本会提示并仅保留 AnyTLS 功能。

## 目录

- `sing-box-proxy-manager.sh`：兼容旧习惯的入口脚本，实际实现位于 `scripts/`
- `scripts/sing-box-proxy-manager.sh`：主脚本（菜单与通用能力）
- `scripts/modules/vless_reality.sh`：VLESS + Reality + Vision 模块
- `tools/`：辅助脚本，例如导入配置的 HTTP 服务
- `docs/reference/`：整理后的上游参考文档
- `data/`：运行时生成的元数据和客户端导入文件，仅远端会使用

## 远端目录建议

远端机器 `/root/sing-box-proxy` 与本地保持同样结构：

- `scripts/`
- `scripts/modules/`
- `tools/`
- `docs/reference/`
- `data/metadata/`
- `data/client-import/`
- `data/client-import-publish/`
- `archive/`：不再直接使用、但先保留的旧文件
