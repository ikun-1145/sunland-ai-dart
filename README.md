# Sunland AI App

Sunland AI 的 Flutter 客户端。DeepSeek 对话继续通过
`https://api.sunland.dev`，Symbolic Core 则只在
`https://ai-core.sunland.dev` 的 Cloudflare Worker 中运行；APK 不再包含
本地 Core、隐藏 WebView Runtime 或 Core JavaScript 资源。

## 数据与身份

- 应用 JWT 仍由现有登录 Worker 签发和刷新。
- 客户端用应用 JWT 换取 15 分钟 Supabase 数据访问 Token，并在用户切换、
  退出登录或 401 后清除旧 Token 与订阅。
- Sunland 的知识、称呼记忆和语义 Context 只通过远程 AI API 访问。
- 首次远程请求会幂等迁移旧本地状态；收到匹配回执后才删除旧数据，损坏数据
  会保留在设备上。
- `webview_flutter` 仅用于 GeeTest 验证码页面。

## 本地验证

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

现有 API Worker 的数据库 Token 与激活码接口位于 `worker/`，可运行：

```bash
cd worker
npm test
```

部署 Worker 时，`JWT_SECRET`、`SUPABASE_JWT_SECRET`、
`SUPABASE_SERVICE_ROLE_KEY` 以及其他服务密钥必须使用 Cloudflare Secret，
不得写入仓库或 APK。

## 发布门槛

`bump_version.sh --target 1.3.0+28 --dry-run` 只验证环境，不修改版本。正式
发布必须取得 v1.2.1+27 的历史 keystore、alias、密码和参考 APK；脚本会在
测试、Release APK 构建及签名证书匹配后才提交、推送和创建 Release。

APK 经中国大陆下载验证后，才可使用 `--promote` 更新网站 `update.json`。
不要创建替代 keystore，也不要在强制升级验证前执行旧表的延后 RLS 迁移。
