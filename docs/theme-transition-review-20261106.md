# 主题切换与底部导航修复记录

工作分支为 `fix/theme-safe-area-transition-20261106`。本轮保留 `daca0bad` 和 `0e814264`，在其上继续修复。当前提交只涉及主题遮罩、背景、安全区域、导航相关 UI 和对应测试。此次交付仅提交源码及静态检查，等待用户另行明确要求后构建。

## 初步修复检查与根因证据

`daca0bad` 把 TimelineView 限制到遮罩内部，避免页面每帧随进度更新，这个方向正确。仍有以下可从源码确认的问题。

- 主题按钮的位置取自 `linyu.theme` 坐标空间，但遮罩自身忽略安全区域后，其原点向状态栏区域移动。原代码直接复用按钮坐标，圆心与实际按钮发生偏移。
- 内容切换依靠两次固定休眠，遮罩进度却使用墙上时钟。首帧准备、主线程调度或场景切换时，两者可能不同步。
- 胶囊导航还有独立的 200ms 深浅色补间，与根页面在扩散阈值切换颜色的机制不一致。
- 原自定义背景是根 ZStack 的前景子项，并通过 GeometryReader 忽略全部安全区域。背景扩展参与根布局，使背景、页面和导航 inset 的范围难以分离。背景改放在根 inset 之外的 background 后，前景保持系统提供的安全布局，背景独立延伸到底部。

`0e814264` 把导航 inset 从页面切换/裁切链移到根视图，保留该改动。当前页面的 `.clipped()` 只覆盖页面，导航由根层 inset 负责。现有导航高度与底部间距保留，未增加用于覆盖断层的固定底部色块。

以上是源码中确认并修复的布局和时序缺陷。仅凭源码无法确认真机大片浅色区域是否还包含 LiveContainer 宿主窗口的额外背景。本项目入口是 SwiftUI App，本次检查范围内没有额外 UIWindow 或 additionalSafeAreaInsets 配置。宿主实际窗口、hosting view 边界及安全区域值仍需在 LiveContainer 真机上核查。

## 与 Android v3.1.0 的对应

本地原版固定基准为 `v3.1.0`，提交 `761ae9b51bb0168b5a4de63a91f5168328107234`。也检查了本地上游 `ff5f8befb2416a21955927c54677e26740a4002a`，CircularRevealTheme.kt、Theme.kt、AppBackgroundLayer.kt 在这两个版本之间没有变化。MainActivity.kt 中内容切换点的状态栏更新和页面状态在主题容器外持有的方式也已阅读。

| 原版机制 | iOS 实现 |
| --- | --- |
| 初始遮罩先绘制一帧 | UIView 首次 draw 完成后，显示刷新回调才开始计时 |
| 650ms、CubicBezierEasing(0.4, 0, 0.2, 1) | 单调显示时钟和同一贝塞尔曲线，正常绘制期为 650ms |
| 进度只驱动 drawWithContent | CADisplayLink 仅更新 UIKit 遮罩的进度和 setNeedsDisplay；进度不写入 SwiftUI State 或 ObservableObject |
| 前 20% 渐显旧背景，跨阈值切换内容 | 遮罩到达缓动进度 0.2 时只通知一次预览；SwiftUI 提交目标主题前保持完整旧背景遮罩 |
| 半径由 20% 至 100% 展开 | 同一公式，覆盖四个角的最大半径乘 1.15 |
| 内容和状态栏共同切换 | palette、内容 colorScheme 和 preferredColorScheme 由同一个 displayDark 驱动，并关闭该节点的隐式补间 |
| 内容只挂载一次 | 原页面分支和 model 持有位置保留；只有遮罩使用单次过渡标识 |
| 动画中忽略重复主题点击 | 点击时立即锁定，完成后解除；其他程序性主题修改在当前过渡后按最终请求收敛 |

原版来源分别为 [CircularRevealTheme.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/ui/theme/CircularRevealTheme.kt)、[Theme.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/ui/theme/Theme.kt)、[MainActivity.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/MainActivity.kt)、[AppBackgroundLayer.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/ui/AppBackgroundLayer.kt)。

必要平台差异如下。

- iOS 使用 UIView 绘制和 CADisplayLink 对应 Compose 绘制阶段。显示回调使用 common 模式，并随遮罩退出释放。 [Apple CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink)
- 背景和遮罩忽略容器安全区域，前景仍响应键盘安全区域；圆心转换成全屏遮罩的局部坐标。 [Apple 背景与安全区域](https://developer.apple.com/documentation/swiftui/adding-a-background-to-your-view)
- 开启减少动态效果时即时切换。应用离开活跃状态或窗口尺寸改变时，将进行中的过渡收敛为目标主题，保持页面实例。iPad 窗口拖拽或旋转中可因此看到扩散提前完成。
- 主题偏好的写入时机保留当前 iOS 的点击即保存行为。Android 在扩散完成后保存；iOS 的可见颜色仍在 20% 节点切换。
- 操作系统负责 iOS 状态栏和 Home Indicator 的最终绘制。其实际变化帧，以及 LiveContainer 是否接管状态栏样式，均须真机验证。

## 修改文件与提交

| 提交 | 文件 | 内容 |
| --- | --- | --- |
| `24509df` | OriginalRootView.swift、LinYuDesignSystem.swift | 根层背景覆盖 inset；背景只忽略容器安全区域；移除导航自身的主题补间 |
| `75578ce` | LinYuThemeHost.swift、LinYuRevealDrawing.swift | 独立遮罩、首帧和预览节点同步、圆心换算、减少动态效果、窗口及生命周期处理 |
| `75578ce` | ThemeRevealTests.swift、ThemeTransitionTests.swift | 绘制和交互回归用例，等待 macOS/Xcode 执行 |

## 验证状态

已在当前 Windows 环境完成以下检查。

- 六个变更 Swift 文件均通过 tree-sitter Swift 语法树解析，未发现 ERROR 或缺失节点。此检查不包含 Swift 类型检查或链接。
- `git diff --check` 通过。
- 独立数值核对贝塞尔曲线中点为 0.775561311，并核对 320×568、344×640、440×956、820×1180、1180×820 的两类圆心位置能够覆盖四角。数值核对没有执行 Swift 运行时。
- 修改文件范围核对通过。模型、登录、蓝牙、消费结算、协议、网络和工作流文件不在此次改动范围。
- 当前分支的工作流事件已检查，IPA 工作流仅有 workflow_dispatch，另外的 push 工作流限定在其他分支。本轮没有发起 Actions 或打包命令。

已添加但尚未执行的测试如下。

- ThemeRevealTests 验证曲线、首帧前不推进、20% 节点只通知一次、等待 palette 提交、结束只通知一次。
- 同一套测试用生产绘制函数检查浅/深旧背景在进度 0、0.2、0.6、1 的透明区域与底部边缘，生成绘制层截图附件；检查窄屏、横竖屏和大屏的圆形覆盖。
- ThemeTransitionTests 使用现有模拟器 Mock 登录，验证两个方向及快速连续点击，依次访问首页、账单、我的和设置，检查导航按钮存在、在窗口内且可点击，并保存页面截图。

当前环境没有 Swift 编译器、Xcode、iOS 模拟器或连接的 iPhone。因此新增 XCTest、UI 测试、实际截图、帧率和真机体验均未标记为通过。

后续取得运行环境后需要完成以下验收。

| 场景 | 状态 |
| --- | --- |
| 小屏与大屏 iPhone 的浅→深、深→浅、快速点击 | 待模拟器与真机验证 |
| 首页、账单、我的、设置的实际过渡首帧、中间帧和结束帧 | 待录屏/截图验证 |
| 自定义背景关闭和开启，包含亮度、模糊、透明度组合 | 待运行验证 |
| iPad 横竖屏、窄分屏、窗口连续调整 | 待运行验证 |
| 减少动态效果、后台/前台切换、系统主题变更 | 待运行验证 |
| LiveContainer 底部安全区域、宿主窗口与状态栏 | 待用户真机验证 |
| 平均帧率、丢帧和主线程开销 | 待 Instruments/真机录屏测量 |

本轮没有生成新的 IPA。待用户明确要求后，再统一执行 Xcode 构建、回归测试和打包。
