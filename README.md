# Float iOS Test Shell · v0.1.0

独立 iPhone `WKWebView` 原生容器实验项目，**不包含 Float 站点源码、不含用户存档、不含登录信息**。

> **当前交付物是可供 macOS GitHub Actions 编译的源码和工作流，而不是已经验证可安装的 IPA。** 本地只完成 Swift 语法解析及静态配置检查；完整 Xcode 构建、Sideloadly 签名、iPhone 真机行为均需要下一步实测。

## 设计目的

- 使用 iOS `WKWebView` 加载唯一主站 `https://aivirtualphone1130.netlify.app/`。
- 网页业务代码、GitHub main 更新、Netlify 部署机制保持不变；新网页版本在下次正常导航/手动刷新并完成缓存更新后生效，**不保证 push 后立即热更新**。
- `WKWebsiteDataStore.default()` 持久化 WebKit 数据；不清理 IndexedDB、缓存、cookies，不采用 non-persistent 浏览。
- 测试容器使用独立 Bundle ID `chat.auren.float.testshell`，不会读写已有 Safari 主屏幕 PWA 的存储。
- 捕捉 `webViewWebContentProcessDidTerminate`，将进程异常记录到独立原生日志；不把该回调误写为已证实 Jetsam/OOM。
- 崩溃后仅展示原生恢复界面，**不自动刷新**。刷新必须经过确认，提醒可能打断尚未完成的 AI 生成。
- WKDownloadDelegate 保存网站响应或 `blob:` 下载到 App 的 Documents/FloatExports；成功后弹出系统分享菜单以保存到「文件」。
- 不注入 JS/CSS、不篡改 UA、不改变 Float 的 Prompt、聊天或支付逻辑。

## 最快路径（只有 Windows + iPhone）

详见 [WINDOWS_BUILD_INSTALL.md](WINDOWS_BUILD_INSTALL.md)：

1. 把本目录作为**新的独立 GitHub 仓库**上传，不要复制进有 1,376 个未提交文件的 Float 工作树。
2. GitHub 仓库的 **Actions → Build iOS test IPA → Run workflow** 使用云端 `macos-15` 与 Xcode 生成 `FloatTestShell-unsigned.ipa`。
3. 下载 Actions 的构建产物并解压后，在 Windows 用 [Sideloadly](https://sideloadly.io/) 用自己的 Apple ID 签名安装到 iPhone。GitHub 仓库和 Actions **绝不需要、也不应存放 Apple ID 密码或签名证书**。
4. 首次运行仅做新 App 的空白存储测试，**不要导入生产大存档**；保留原 PWA，不卸载、不清除网站数据。

## 查看原生诊断

在测试 App 中，用 **三根手指同时长按 1.5 秒**，打开原生菜单：

- 导出原生诊断（JSON），仅记录本地时间、页面导航结束、WebKit 进程终止、下载成败等元数据；不记录请求 URL 的查询参数、聊天内容或 API key。
- 检查网站更新（手动刷新）；先检查 Float 没有尚未完成的生成。

若 WebKit 网页内容进程被终止，也会出现可导出原生诊断的恢复页。

## 数据安全边界

1. **原 PWA 的 IndexedDB 和 App 自己的 WKWebView 存储天然隔离。** 不存在“安装后自动继承”功能。
2. 网页正常更新不会有意清空 App 容器的数据，但站点自身的数据格式迁移和 WebKit 存储保留仍需独立验证；**无法保证存储绝对不丢失**。
3. Apple ID 侧载的重新签名/覆盖安装：必须保持稳定 Bundle ID + 相同 Apple ID；不要删除已安装 App。后续安装方式改变时数据可能隔离或丢失。
4. 测试期间不要在正式 PWA 中主动制造故障，不要为了对照复制完整的私密存档。
5. GitHub Actions 里生成的是**未签名** IPA，不会直接运行在 iPhone 上。
6. 免费开发者 Apple ID 的侧载签名通常有效约 7 天；续签可能需要 Windows 电脑，具体取决于 Sideloadly 设置。

## 未做的事（需要真机检查）

- Netlify/PWA Service Worker 更新流、WebKit IndexedDB 存储实际隔离与持久性
- iPhone 文件上传选择器、下载 ZIP/图片与 blob URL 保存
- MiniMax/OpenAI TTS 音频、录音、摄像头、通话及 WebRTC 与原 PWA 的功能对照
- 第三方 OAuth / 深度链接：默认把非 Netlify 的顶层导航交给 Safari，授权回跳需要单独实现
- 自定义 iMessage 主题的安全区、输入法键盘、底部 composer 和顶部状态栏
- Web Push、后台执行、音频自动播放：不能假设 WKWebView 与主屏幕 PWA 完全一致
- 真机 WebContent 进程终止证据与 Jetsam 分析（仅凭终止回调不能推断系统原因）
- Xcode 构建、Windows 签名和真实 iPhone 安装（本环境没有 macOS/Xcode）

## 源码及构建入口

- `Sources/BrowserViewController.swift`：WKWebView 容器、恢复视图、下载、导航限制。
- `Sources/NativeDiagnostics.swift`：原生日志，保留最近 64 条元事件。
- `Sources/FloatTestShellApp.swift`：SwiftUI App 生命周期。
- `project.yml`：XcodeGen 工程定义。
- `.github/workflows/build-ios-ipa.yml`：**手动**触发 macOS 编译，生成未签名 IPA。
- `scripts/validate.py`：Windows/Linux 预检，不代替 Xcode。

测试源代码、外部链接均应独立审计后再用于正式数据。
