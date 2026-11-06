# LinYu iOS

**基于 LinYu Android 的原生 SwiftUI 校园用水管理应用**

[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF)](https://developer.apple.com/xcode/swiftui/) [![iOS](https://img.shields.io/badge/iOS-16%2B-222222)](#构建与安装) [![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

LinYu iOS 以开源 Android 项目 [LinYu](https://github.com/yehu-imei/linyu) 为基础移植，目标是尽可能还原原版的界面、功能和交互，本轮交付范围为 iPhone 测试版；iPad 暂不验收。

iOS 移植与维护由 **Cra3y** 负责，Android 原版作者为 **yehu-imei**。本项目是第三方客户端，与校园及设备服务运营方没有官方隶属关系。App 内名称保留为「淋浴」。

## 功能与当前边界

| 功能 | 实现及验证范围 |
| --- | --- |
| 手机号登录与账户管理 | 验证码/密码登录、会话保存、账户信息及相关设置 |
| 校园蓝牙水表 | Core Bluetooth 扫描、台账识别、设备状态核对 |
| 热水器开启与关闭 | 已实现 BLE 控制与必要回执确认；真实设备兼容性仍需逐校验证 |
| 用水时长及状态 | 使用中、阀门待核实、已关闭待结算等界面；历史异常记录需谨慎核实 |
| 消费记录及账户信息 | 钱包、账单、详情和账户信息同步，依赖校园服务端返回 |
| 异常交易恢复 | 保存交易凭据并提供恢复入口；整合 v0.4.5 的结算、计时与历史订单修复，上传结果未知时优先只读核实 |
| 主题与自定义背景 | 深浅主题、独立 HOME/SHOWER 背景、主题色、亮度、模糊和透明度；新渲染与动画仍须真机验证 |
| 本地通知与桌面组件 | 提供 UserNotifications / WidgetKit 实现；LiveContainer 包不含 Widget 扩展，通知能力受宿主权限及签名限制，常规签名包仍待完整验证 |
| 响应式界面 | 按窗口尺寸适配小屏/大屏 iPhone、iPad 和横竖屏；布局渲染测试通过，横屏登录用例已通过，本轮暂不适配 iPad，已有密码模式触摸问题将作为已知限制保留，实际分屏、窗口调整及其他设备形态仍待验证 |

BLE 连接、开关阀和设备清账需要靠近原水表。上传结果未知时，账单缺失或金额为零不能直接证明未记账。不同校园、固件及宿主环境的实机结果可能不同。

## 源码、构建与发布

**[下载 v0.4.6（Build 10）iPhone 测试版](https://github.com/CarpediemDyn/linyu-ios/releases/tag/v0.4.6)** · [直接下载 IPA](https://github.com/CarpediemDyn/linyu-ios/releases/download/v0.4.6/LinYu-LiveContainer.ipa) · [完整检查报告](docs/release/0.4.6-final.md)

| 类别 | 当前状态 |
| --- | --- |
| 默认源码 `main` | **v0.4.6（Build 10）**，整合结算、自动名称、主题、背景与署名分支；后续发布资料更新不改变产品代码 |
| 已构建产品源码 | 标签 `v0.4.6`，`05b4563830892110e69e76ad950a61e349da8395`；整合分支 `release/0.4.6-20261106` |
| 最近成功 IPA | **v0.4.6（Build 10）**；[Actions 42227337569](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42227337569) |
| 旧成功基线 | v0.4.5（Build 9），源码 `c6d6c3302aa92161cd6ff48656a671cbbcf47de5`，保留为 `baseline/v0.4.5-build9` |
| GitHub Release | 已发布 **v0.4.6 iPhone 测试版（Pre-release）**，不宣称正式稳定版或全部硬件验收 |

最终固定源码通过 **177 项 iOS 单元测试、全部 8 项 UI 测试**，涵盖快/慢登录、失败恢复、防重复提交、横屏输入、历史订单恢复、双向主题与实际导航切页；Ubuntu/macOS 各通过 51 项核心和 8 项打包测试。51 Core 已包含在 177 中，不重复计数。全部自动化使用 Mock 网络/BLE，不操作真实校园水表或产生消费。

IPA 已验证 arm64 / iphoneos、AppIcon、严格 ad-hoc 签名、ZIP CRC、全部成员哈希与来源提交。未登录访问 Release 并重新下载 IPA 校验通过；校验文件及报告随 Release 提供。首次及后续失败记录保留在 [继续验证记录](docs/release/0.4.6-validation.md)。

本轮按用户要求暂缓 iPad 适配。iPad 密码模式切换后已有登录按钮触摸问题尚未解决，不能把现有宽屏布局视为 iPad 可用性承诺。447/450 等真实历史订单、校园服务、设备写回及 LiveContainer 后台/通知仍需原手机与原水表验证。

## 构建与安装

使用 Swift / SwiftUI、Core Bluetooth 和 Apple 系统框架。最低部署版本为 **iOS 16.0**；本测试版验收范围为 iPhone。完整工程构建需要 macOS、Xcode 和 XcodeGen。

```sh
brew install xcodegen
swift test
xcodegen generate --spec project-livecontainer.yml
open LinYuLiveContainer.xcodeproj
```

在 Xcode 选择可用 iPhone 模拟器运行测试。`project-livecontainer.yml` 生成 LiveContainer 工程，`project.yml` 提供常规应用与 Widget 工程；后者需要自行配置 Apple 开发团队、签名及 App Group。

仅在明确授权打包后，在 GitHub Actions 的 **Build LiveContainer IPA** 工作流选择已固定的分支、完整源码 SHA、macOS runner 和模拟器类型。默认 `tests_only=true` 仅测试、不生成 IPA；明确授权打包时才设为 `false`。`preflight_only=true` 仅运行 Ubuntu 资源/配置、打包与 Mock 核心检查，不分配 Mac、不生成 IPA。正式构建先通过同一预检，再运行全部 iOS/UI 测试；测试成功才生成 arm64 真机包、验证 ad-hoc 签名并输出 `LinYu-LiveContainer.ipa`。失败不会自动重试。

从上述 Release 下载 `LinYu-LiveContainer.ipa`，在 iPhone 的 LiveContainer 导入。已有安装请使用替换/升级并保留原应用数据，以继续读取本地交易恢复记录。无需从 Actions 下载或登录 GitHub。可用 Release 附带的 `.sha256` 核对文件。

LiveContainer 包的 ad-hoc 签名用于宿主加载，并非 App Store / TestFlight 分发签名，不能按普通 Apple 签名安装包使用。iOS 后台执行、通知和桌面组件受系统与宿主限制。更新与测试版的最终下载以 [GitHub Releases](https://github.com/CarpediemDyn/linyu-ios/releases) 为准；未出现的制品不代表已经生成。

## 开发与维护

- **iOS Port & Maintainer — Cra3y**，GitHub 账号 [CarpediemDyn](https://github.com/CarpediemDyn)。
- **Original Android Project — yehu-imei**，原版 [yehu-imei/linyu](https://github.com/yehu-imei/linyu)。
- 业务移植以 Android 原版为主要依据，平台不兼容部分采用必要的 iOS 适配。
- 缺陷反馈请提供应用版本、构建号、iOS 版本及脱敏后的复现步骤。交易恢复问题请保留本地数据，公开 Issue 中请勿附带验证码、令牌、账号账单或完整协议报文。

[模块映射](docs/ui-parity/ANDROID_IOS_MAP.md) · [WidgetKit 差异](docs/ui-parity/WIDGETKIT.md) · [资源来源](docs/ui-parity/RESOURCE_LICENSES.md) · [公开前审计](docs/public-readiness-20261106.md)

## 许可证与致谢

本项目遵循 [MIT License](LICENSE)，保留原版 **LinYu Contributors** 版权声明，并注明 Cra3y 的 iOS 移植贡献。Android 原版功能、设计与素材贡献归原作者及相应贡献者。

Google Material Icons 遵循 Apache-2.0，完整许可与资源来源已保留。Apple 系统框架按其平台条款使用。详见 [署名与第三方声明](NOTICE.md)。

项目地址为 **https://github.com/CarpediemDyn/linyu-ios**。
