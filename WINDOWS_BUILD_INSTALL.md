# Windows → GitHub Actions → iPhone：首次构建与安装

## 0. 只动独立目录

把下载 ZIP 解压到一个**新的文件夹**，例如 `C:\Users\<你>\Desktop\Float-iOS-TestShell`。

**绝对不要在** `ai-virtual-phone` 工作树下执行以下 git 命令；该工作树有 1,376 个需要保护的无关改动。

## 1. 在 GitHub 新建独立仓库

到 `https://github.com/new`，名字建议 `Float-iOS-TestShell`，Owner 使用自己的账号（例如 `Aurenchat`）。不要勾选初始化 README（ZIP 已有）。

- Public 仓库在 GitHub 标准 macOS 运行器上一般不额外计 Actions 使用分钟；但项目源代码和 Action 产物的访问权限公开。这个仓库只包含公开站点 URL 和原生壳，不包含存档。
- Private 仓库也可以，但 macOS runner 会计入你账号的 Actions 配额或产生额外费用。选择前看 GitHub Billing。

在解压目录打开 Windows PowerShell，执行以下示例；如果仓库地址不同，替换 URL：

```powershell
cd 'C:\Users\<你>\Desktop\Float-iOS-TestShell'
git init -b main
git add README.md WINDOWS_BUILD_INSTALL.md VERIFY_ON_IPHONE.md project.yml Sources Resources scripts tests .gitignore .github
git commit -m 'Add isolated Float iOS WKWebView test shell'
git remote add origin https://github.com/Aurenchat/Float-iOS-TestShell.git
git push -u origin main
```

这些指令只用于**新仓库**。如使用已有目录，需要先确认 git 状态和远端。

## 2. GitHub 云端编译

打开新仓库的 **Actions → Build iOS test IPA → Run workflow → Run workflow**。

- 工作流安装 XcodeGen，调用 `xcodebuild` 使用 iPhoneOS SDK 生成 `.app`。
- 使用 `CODE_SIGNING_ALLOWED=NO`，将 `.app` 打包成 `Payload/FloatTestShell.app` 并生成 `FloatTestShell-unsigned.ipa`。
- workflow 成功后，在该 run 的 Artifacts 区下载 `FloatTestShell-unsigned-ipa`；外层下载通常是一个 ZIP，解压找到 `.ipa` 文件。
- 如果任何步骤失败，把完整 workflow 日志带回来：**不要改动 Float 主仓库**，我们只修这个测试壳。

**必须注意：** GitHub Actions 报绿只代表远端 macOS 编译通过，不代表 iPhone 已安装或 WKWebView 行为正确。

## 3. Windows 签名/安装

- 从 `https://sideloadly.io/` 获取官方 Windows 安装程序。
- 按其文档安装必要的 iTunes/iCloud 桌面组件（官网提示避免 Microsoft Store 版）并通过 USB 连接 iPhone。
- 打开 Sideloadly，选中真实 iPhone，拖入 **`.ipa`**（不是 GitHub 下载时的外层 zip）。
- 用**个人** Apple ID 在 Windows 本地完成签名，按 iPhone 系统提示开启必要的开发者信任/开发者模式（设备和系统版本不同，步骤略有差异）。
- 不要将 Apple ID、签名证书、密码、设备 UDID 写入 GitHub 仓库或发给任何人。

免费 Apple ID 签名通常 7 天，需要续签；Sideloadly 可选自动刷新，要求电脑/设备满足连接条件。

## 4. 首次打开

- 打开新的 **Float Test** 图标，确保和 Safari 主页图标是两个不同的 App。
- 应出现 Netlify 的 Float 网页。**首次为独立空白存储；不应自动看到主屏幕 PWA 的已有聊天。**
- 先测试打开页面、切换 App、关闭重新打开、无需存档的小功能和 iMessage 主题 UI。
- 三指长按 1.5 秒，导出 Native diagnostics，确认有 `shell_opened`、`navigation_finished` 事件。
- 如测试壳闪退或网页进程中断，把测试壳的原生诊断 + Float 页面诊断对齐。

## 5. 网站更新与后续 IPA 更新

- 日常 Float TypeScript/CSS 功能变更：`Aurenchat/ai-virtual-phone` → Netlify 正式部署 → **测试 App 的网页在下次正常加载/确认刷新后更新**；不重编 IPA。
- iOS 容器 Swift 本身变化：更新这个独立仓库，重新 Run workflow，签名安装新版 IPA；保持 Bundle ID 和 Apple ID 不变，并尽量覆盖安装，不能卸载后安装。
- 在当前没有做经过验证的迁移方案之前，**不要把测试壳当作正式唯一的数据存储位置。**
