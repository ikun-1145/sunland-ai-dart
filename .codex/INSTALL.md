# Codex 工程环境安装

仓库中的 `AGENTS.md`、`.agents/skills/`、`.codex/agents/` 和 `.codex/config.toml` 会被当前 Codex 客户端自动发现，不需要复制到用户主目录。

## 1. 安装或更新 Codex

仅在本机尚未安装或需要更新时运行 OpenAI 官方安装器：

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version
```

## 2. 安装项目依赖

确保 Flutter `bin` 已加入 `PATH`。本机当前 Flutter 位于 `/Users/liuxize/development/flutter/bin`：

```bash
cd /Users/liuxize/sunland_ai_app
export PATH="/Users/liuxize/development/flutter/bin:$PATH"
flutter --version
flutter pub get
(cd worker && npm ci)
```

## 3. 登录项目 MCP

文档 MCP 不需要登录。Cloudflare 可观测性和项目限定的 Supabase 只读 MCP 使用 OAuth：

```bash
cd /Users/liuxize/sunland_ai_app
codex mcp login cloudflare-observability
codex mcp login supabase-readonly
codex mcp list
```

不要把 OAuth Token、PAT、API Token 或 Secret 写入仓库。Supabase MCP 只允许项目限定的文档、只读数据库和调试能力；Cloudflare 日志工具的每次调用都需要批准。

如果 `codex mcp login supabase-readonly` 再次出现 `No authorization support detected`，先检查 `https://api.supabase.com` 的 TLS/代理连通性，再重试 OAuth；不要通过更换正确的 MCP URL 或把 PAT 写入配置来绕过网络问题。

## 4. 验证项目基线

```bash
cd /Users/liuxize/sunland_ai_app
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
(cd worker && npm test)
git diff --check
```

重新启动 Codex 后，在项目根目录运行 `codex`。可用 `$sunland-flutter-workflow`、`$sunland-edge-workflow`、`$sunland-release-workflow` 或 `$sunland-team-review` 显式调用项目 Skill；需要并行审查时，要求 Codex 使用对应的项目子 Agent 并等待全部结果。
