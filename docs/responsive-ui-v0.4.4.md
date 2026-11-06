# LinYu iOS v0.4.4 响应式界面验收

布局判断使用安全区内实际可用的宽高。小于 360 pt 时缩小页面边距，并把设备恢复操作放到单独一行。高度小于 460 pt 时减少纵向留白。登录、首页、账单、个人中心和用水页分别限制宽度，宽窗保持居中。

| 窗口样本（pt） | 覆盖场景 |
| --- | --- |
| 320×568、344×720、344×640 | 小屏 iPhone、窄窗口及列表 |
| 390×844、420×912、440×956 | 标准手机、Air 尺寸代理、大屏手机 |
| 466×678、626×890 | Duo 外屏、内屏窗口代理。以公开像素尺寸按 3 倍缩放构造测试尺寸 |
| 744×1133、820×1180、1032×1376 | iPad mini、iPad / Air、iPad Pro 尺寸代理 |
| 844×390、812×320、1180×820、1024×768 | 手机横屏、平板横屏、宽窗口 |
| 320×310、344×290 | 低高度详情弹窗、放大字体的长错误弹窗 |

尺寸代理验证布局如何响应宽高变化。Duo 的折叠过程、iPad Stage Manager 和系统分屏的真实拖拽、不同系统版本的键盘与安全区，以及实体摄像头横屏预览仍需在对应环境复测。

## 布局变化

- 登录页原先整页延伸到安全区外，并通过负偏移调整视觉位置。现仅背景全屏，登录内容可在安全区内滚动，横屏和键盘弹起时减少表单留白，短窗口内可直接收起键盘。
- 底部导航原先覆盖在页面之上，滚动页各自留约 100 pt 空白。现由安全区插入给胶囊留出实际空间，底部内容可以滚动到导航上方。
- 宽屏卡片原先可随页面一直拉宽。现限制内容列宽，背景仍延伸到屏幕边缘。保留原有胶囊导航和单列阅读顺序。
- 长弹窗现可在可用高度内滚动。窄窗和无障碍字体下，设备名称、阀门状态和恢复按钮可分行。用水页的结束和继续结算按钮允许随字体扩高。
- 扫码提示及控制留在安全区内，短窗口缩小取景框，视频预览随界面方向调整。摄像头采集和二维码识别沿用原流程。

## 参考资料

- Notion 将可读内容宽度与窗口宽度分开。LinYu 借鉴居中内容列和宽屏留白。[Notion 页面宽度](https://www.notion.com/help/customize-and-style-your-content)
- Telegram 的 iPad 布局在宽窗口可显示独立列表，其公开问题记录也反映了键盘和窗口控件会挤压内容。LinYu 使用同一滚动列表，并优先保护输入区及顶部操作。[Telegram iPad 窗口记录](https://bugs.telegram.org/c/66347)
- Spotify 的平板布局随方向重新组织，主要导航维持熟悉位置。LinYu 保留底部导航，并分别限制卡片和控制区宽度。[Spotify 平板布局](https://newsroom.spotify.com/2026-04-16/new-tablet-app-experience/)
- Discord 将移动端常用入口集中在底部。LinYu 保留可点击的底部胶囊，在安全区为其留位。[Discord 移动端导航](https://discord.com/blog/improving-our-mobile-experience)
- Outlook 对 iPad Split View 单独适配。LinYu 的窄窗行为由可用宽度决定，平板可继续用同一套控件。[Outlook Split View](https://support.microsoft.com/en-us/outlook/what-is-split-view-for-ipad-ios)
- Apple 的布局指南给出了安全区和宽窗内容居中的原则。Duo 尺寸代理依据 Apple 公布的内外屏像素分辨率。[Apple 布局指南](https://developer.apple.com/design/human-interface-guidelines/layout) · [iPhone Duo 技术规格](https://www.apple.com/iphone-duo/specs/)

## 构建与验证

- 源提交为 `b1429a2`，IPA 版本为 `0.4.4 (8)`，最低系统 iOS 16，设备声明包含 iPhone 和 iPad。CI 已严格验签，下载后核对包成员哈希、平台和 SHA-256。
- iPhone 16 Pro 和 iPad Pro 11 英寸（M4）模拟器均通过 33 项核心测试、115 项 iOS 单元与集成测试、6 项 UI 测试和 8 项打包测试。模拟器 UI 使用 Mock 登录。
- 横屏登录验证输入在旋转后保留，可以收起键盘并滚动提交。另验证了首页、账单及设置页导航。尺寸代理截图覆盖设备列表、阀门状态待核实、继续结算、计时结束按钮、扫码权限界面和长错误弹窗。短窗测试另外验证了实际可滚动范围，并在滚动到底后截取操作区。

[iPhone 构建与测试](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42152067766) · [iPad 构建与测试](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42152071810)

`SHA-256 d294af4853540136b7413dacc9601a797b1601d48f8c38f481e12a8d5db1dac0`
