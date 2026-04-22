# sing-box-proxy

这个目录现在按用途分层，根目录只保留入口和说明。

## 目录

- `sing-box-proxy-manager.sh`：兼容旧习惯的入口脚本，实际实现位于 `scripts/`
- `scripts/`：主脚本
- `tools/`：辅助脚本，例如导入配置的 HTTP 服务
- `docs/reference/`：整理后的上游参考文档
- `data/`：运行时生成的元数据和客户端导入文件，仅远端会使用

## 远端目录建议

远端机器 `/root/sing-box-proxy` 与本地保持同样结构：

- `scripts/`
- `tools/`
- `docs/reference/`
- `data/metadata/`
- `data/client-import/`
- `data/client-import-publish/`
- `archive/`：不再直接使用、但先保留的旧文件
