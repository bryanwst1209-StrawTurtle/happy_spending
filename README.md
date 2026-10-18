# happy_spending

无广告、免费、干净的 iOS 记账 app(iOS 26+,SwiftUI + SwiftData)。

- 设计文档:`docs/superpowers/specs/2026-10-10-bookkeeping-app-design.md`
- 实现计划:`docs/superpowers/plans/2026-10-10-happy-spending-v1.md`
- 手动检查清单:`docs/manual-test-checklist.md`
- Apple Pay 自动入账设计:`docs/superpowers/specs/2026-10-13-apple-pay-auto-record-design.md`
- 屏幕识别与通知自动入账设计:`docs/superpowers/specs/2026-10-15-screen-and-notification-auto-record-design.md`
- 微信支付消息列表记账设计:`docs/superpowers/specs/2026-10-15-wechat-list-screen-record-design.md`
- 待归类设计:`docs/superpowers/specs/2026-10-16-pending-categorization-design.md`

## 结构

- `Packages/HappySpendingCore`:数据模型与全部可测试的逻辑(Swift Package)
- `HappySpending`:SwiftUI 界面(记账、账单、统计、设置)
- `project.yml`:XcodeGen 配置,`.xcodeproj` 由它生成,不入库

## 常用命令

```bash
# 跑 Core 的全部测试(不需要模拟器)
cd Packages/HappySpendingCore && swift test

# 生成 Xcode 工程(需要 brew install xcodegen)
xcodegen generate

# 安装 git 钩子(克隆后运行一次):之后切换分支、合并时会自动重新生成工程
sh scripts/install-git-hooks.sh

# 编译 App
xcodebuild -project HappySpending.xcodeproj -scheme HappySpending \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 装到自己的 iPhone

1. `xcodegen generate` 后用 Xcode 打开 `HappySpending.xcodeproj`
2. Signing & Capabilities 里选自己的 Apple ID 团队
3. 连接 iPhone,选它为运行目标,点 Run
4. 免费账号的证书 7 天过期,过期后重新 Run 一次即可

## 在模拟器里运行

本机需要先在 Xcode → Settings → Components 下载 iOS 26 模拟器运行时。
