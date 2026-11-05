# Android → iOS 全界面映射与验收台账

目标：官方 v3.1.0。以下是修改前的基线盘点，不能将“有代码”视为已完成视觉验收。

后续实现在 `ui/android-parity`，当前已实现内容、模拟器证据及待真机检查见 [VISUAL_QA.md](VISUAL_QA.md)。
状态定义：已有=现有功能接口；视觉不一致=需要重建视图；缺失=未实现对应控件/状态；待验证=需要实际截图或交互结果。后续逐行附截图和测试证据，不以编译结果替代视觉结果。

| Android 页面/组件 | iOS 基线对应 | 功能/视觉基线 | 必须验证 |
|---|---|---|---|
| LoginScreen：短信登录 | AccountView | 已有接口；Form视觉不一致 | 固定白卡、蓝渐变、键盘/错误/加载 |
| LoginScreen：密码登录 | AccountView | 已有接口；视觉不一致 | 切换清秘密、自动填充、失败清字段 |
| LoginViewModel：验证码发送 | AuthManager.sendSMS | 接口已有；60秒倒计时缺失 | 非11位、请求失败、固定按钮宽 |
| MainScreen 标题/扫码/刷新 | OriginalRootView.home | 视觉不一致，刷新入口缺失 | 原Hualala副标题、40圆按钮 |
| ActiveOrderCard | OriginalRootView.home | 已有订单；卡片/恢复交互不一致 | 与上次设备互斥、恢复入口 |
| LastDeviceCard | OriginalRootView.home | 已有；文案/图标/布局不一致 | MAC尾部保留、开始按钮 |
| DeviceCard/DeviceGlyph | OriginalRootView.home | 已有；原矢量和信号颜色缺失 | 原RSSI阈值、设备名、MAC |
| PermissionHint/空态/扫描行 | OriginalRootView.home | 部分合并，状态和图例缺失 | iOS权限适配、扫描/停止/空态 |
| 寝室过滤行 | OriginalRootView.home | 过滤已有；取消入口缺失 | 清除过滤即时生效 |
| FloatingPillNavBar | OriginalRootView | 视觉不一致 | 260宽、横图文、账单、弹簧/遮挡 |
| DeviceDetailDialog | OriginalDeviceDetail | 系统sheet/Form不一致 | 原SN/MAC/状态/预扣/确认 |
| DeductConfirmDialog | StartFailure/Wallet alerts | 已有；未知金额仍可确认需修正 | 无效总额禁用、单笔/批量 |
| 启动失败/无可补扣账单 | OriginalStartFailureView | 系统列表不一致 | 不扩张补扣范围/不自动扣款 |
| 会话失效/异地登录提示 | AuthManager/根视图 | 状态差异；弹窗缺失 | 保留现有会话安全行为 |
| WalletScreen 余额/来源 | OriginalWalletView | 已有；文字/间距不一致 | 一卡通/钱包/估算/未设置 |
| 手动填写余额/余额说明 | OriginalWalletView | 有入口；弹窗不一致 | 输入/保存/时间/非假余额 |
| SpendingTrendCard | OriginalWalletView chart | 折叠、3指标、选点/峰值等缺失 | 7天/本月、柱/线、空/负/零值 |
| 账单列表/加载/空/失败 | OriginalWalletView | 已有；视觉不一致 | 保留历史快照、不覆盖旧数据 |
| 账单详情 | OriginalWalletView sheet | 系统sheet不一致 | 全字段、标签、未知状态 |
| 单笔与批量补扣 | OriginalWalletView | 功能已有；确认待修正 | 有限已知总额，处理中锁定 |
| UserScreen 我的账号 | OriginalProfileView | 卡片已有；结构不一致 | 4行资料、三个默认卡、标题 |
| 账号管理展开 | OriginalAccountManagement | 原内联变为sheet | 原展开/收起、入口文案 |
| 更换手机号 | OriginalAccountManagement | 接口已有；确认/倒计时缺失 | 新号短信type5、提交锁定 |
| 修改密码/短信重置 | OriginalAccountManagement | 接口已有；确认新密码缺失 | 直接/短信切换、错误/提交锁定 |
| UseCodeSection | OriginalProfileView | 已有；字距/分色/展开不一致 | 加载/未领/开关/重新领取 |
| 使用码领取预览 | OriginalCodeCandidateView | 已有；视觉不一致 | 3分钟、换一个、次数、确认/过期 |
| 绑定寝室/附近选择 | OriginalRoomPicker | 已有；列表/弹窗不一致 | 选择、已绑定、解绑确认 |
| 内联卡片编辑/移动/隐藏 | OriginalCardEditor | 独立List不一致 | 上下移、跨页、隐藏项编辑态 |
| SettingsScreen | OriginalSettingsView | 系统Form不一致 | 原卡片/退出/页脚、隐藏底栏 |
| 通知卡/详细设置 | OriginalSettingsView | 接口已有；布局/状态不一致 | 总开关与4子项、iOS授权状态 |
| 消费趋势开关卡 | OriginalSettingsView | 已有；布局不一致 | 与钱包状态联动 |
| CustomBackgroundScreen | OriginalBackgroundSettings | 系统Form不一致 | 主页/使用页、预览、滑条、恢复 |
| theme/背景提色/圆揭示 | OriginalPreferences/Background | palette不一致，揭示缺失 | 650ms、状态保留、两作用域独立 |
| LogViewerDialog | OriginalLogView | 系统List不一致 | 日志/滚动/刷新/导出/清空/空态 |
| 关于项目卡/链接 | OriginalAboutView | 原内联变sheet | 全文、仓库/邮件链接 |
| 应用信息/更新弹窗 | OriginalUpdateView | 功能分发机制不同 | 版本/更新说明/失败/iOS说明 |
| ShowerScreen 使用中 | OriginalShowerView | 控制已有；大布局不一致 | 原渐变、头像/预扣/计时/费率 |
| 自动关停倒计时/结果 | OriginalShowerView/root alert | 部分状态，视觉不一致 | 仅真实状态、未知计时不伪造 |
| 结束确认/结算中/结束结果 | OriginalShowerView | 确认缺失、结果待完整验证 | 确认后原业务调用、失败恢复 |
| QrScanActivity 相机页 | OriginalScannerView | 相机已有；原叠层不一致 | 框角/扫描线/手电/相册/关闭 |
| 扫码权限/拒绝/启动失败 | OriginalScannerView | 状态不完整 | 明确授权、去设置、重试 |
| 相册/无有效码/识别失败 | OriginalScannerView | 部分错误缺失 | 原解析、防重复、成功反馈 |
| LinYuToast | OriginalRootView | 底部4秒与原顶部2.5秒不符 | 单行尾部优先、logo、入退场 |
| Widget 1x1/2x2/2x4 | LinYuWidgets/Shared | 已有原生版本；等效待核实 | 明确尺寸/后台/LiveContainer限制 |

## 验收证据要求
每个页面需记录元素完整性、实际按钮行为、浅/深色、紧凑/大屏、截图来源与已知差异。真实登录、BLE、消费与付款不在视觉夹具中执行。真实账户/设备端验证与模拟截图验证分开记录。

