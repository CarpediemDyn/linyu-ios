# LinYu v3.1.0：登录、首页、导航、扫码与共享弹窗 UI 盘点

本文件只做源码与资源盘点，未修改产品或测试代码。目标是 Android UI 高保真复刻，下面记录的布局、原文、条件分支和反馈方式均是复刻约束，不能改成 iOS 默认 Form/sheet 后视为完成。

## 版本与引用约定

- Android 工作区：`D:\User\Documents\move_to_ios\work\android-upstream`；HEAD `ff5f8befb2416a21955927c54677e26740a4002a`。
- 官方 v3.1.0 的 **commit** 为 `a650066a9624681a0e3404063219435d3717fa98`。`761ae9b51bb0168b5a4de63a91f5168328107234` 是 annotated tag 对象，不能当 commit。
- 已以 `git diff --quiet v3.1.0 HEAD -- <本任务12个界面/辅助文件、theme、AppBackgroundLayer、DeviceModels>` 核对，返回 0，无差异。因此这些文件下列行号同时适用于 v3.1.0 与当前 HEAD。
- `MainViewModel.kt` 有未发布改动；本文注明其 HEAD 行号时只是定位现有实现。涉及官方行为另用 `git show v3.1.0:...` 核对，不能把 HEAD 新 toast 等混入 v3.1.0。
- iOS 工作区：`D:\User\Documents\move_to_ios\work\livecontainer-cloud`。
- 下文 `A/` 表示 Android 工作区下 `app/src/main/java/com/hualala/linyu/`；`AR/` 表示其 `app/src/main/res/`；`I/` 表示 iOS 工作区下 `LinYuIOS/`。每个 `文件:行号` 均按这些绝对根定位。
- 尺寸为 Android 源码 dp，字体为 sp；未给显式字号/高度/圆角的 Material3 控件依赖 Compose BOM `2024.02.01`（`gradle/libs.versions.toml:16`），不是可随意替换的参数。项目没有自定义 Compose Typography/FontFamily；显式文字之外应保留 Android 默认排版并结合 APK 实测。本文不把平台默认值伪装成源码硬编码数值。

## 必须先纠正的 iOS 基线问题

1. **完整 UI 截图被当作默认背景。** `I/Views/OriginalRootView.swift:169-180` 始终请求背景，`I/Models/OriginalBackgroundPalette.swift:19-25` 在 path 为空时回退 `OriginalHome` asset。已实际查看 `I/Assets.xcassets/OriginalHome.imageset/image.png`：是带「淋浴 / Hualala」、余额、假设备卡、扫描状态和底栏的完整 Android 截图。它会与真正 SwiftUI 控件叠加，产生重复 UI 与虚假数据。Android 默认 `enabled=false`（`A/utils/BackgroundState.kt:8-13,69-74`）；只画纯色背景，用户明确启用并存在自定义图片才画图（`A/ui/AppBackgroundLayer.kt:27-35`）。不能用这张截图替代组件实现。
2. **登录视图全部不匹配。** iOS 目前为 `NavigationStack + Form`、标题「校园账号」、Toggle、Section 和调试反馈（`I/Views/AccountView.swift:11-67`）；Android 是固定蓝色全屏渐变、logo、白卡及模式文字切换。应重建原组件层次。
3. **动钱确认分支不匹配。** iOS 在金额无法确认时仍提供扣款按钮（`I/Views/OriginalRootView.swift:231-239`，钱包同类分支 `283-286,351-358`）；Android `DeductConfirmDialog` 在 amount=null 时禁用确认（`A/ui/DeductConfirmDialog.kt:43,68-73`）。此差异必须修正。

## 公共主题、背景与根容器

来源：`A/ui/theme/Theme.kt:15-45,85-109`，`A/ui/theme/CircularRevealTheme.kt:74-161`，`A/MainActivity.kt:79-81,178-237,305-318`。

| Token | Light | Dark |
|---|---|---|
| Background | `#F1F5F9` | `#0E131D` |
| Card | `#B8FFFFFF`（alpha 184/255） | `#BF1D232E`（alpha 191/255） |
| SolidSurface（弹窗） | `#FFFFFF` | `#161B22` |
| Primary | `#0D1117` | `#E6EDF3` |
| Accent | `#2563EB` | `#58A6FF` |
| TextPrimary | `#111827` | `#E6EDF3` |
| TextSecondary | `#6B7280` | `#8B949E` |
| Success | `#22C55E` | `#3FB950` |
| Warning | `#F59E0B` | `#D29922` |
| Danger | `#EF4444` | `#F85149` |
| ActiveBg | `#FFF7ED` | `#1B1F23` |
| SurfaceVariant | `#F0F0F0` | `#21262D` |
| Border | `#14000000` | `#14FFFFFF` |

- home 作用域背景用于首页/账单/我的；shower 作用域用于使用页。图片 Crop 铺满，独立 opacity、blur(dp)、RGB brightness 倍乘；默认 1、0、1。主题提色仅覆盖 Accent，不决定明暗主题。`A/ui/AppBackgroundLayer.kt:37-53`，`A/utils/BackgroundState.kt:26-44`。
- 主内容 edge-to-edge；无自定义 home 背景时状态栏与 Background 一致，有时透明；深色用浅色状态图标。`A/MainActivity.kt:79-81,305-318`。
- Android 初始 LIGHT（不是跟系统）；主题切换从点击位置做圆形揭示，650ms，Bezier `(0.4,0,0.2,1)`；前 20% 旧底色遮罩渐显，20% 切换内容与状态栏，后 80% 圆形半径从 0 扩展至最远角距离×1.15。无 origin 时取 `(屏宽-36dp,48dp)`；动画时禁止再次触发；内容不重建。`A/MainActivity.kt:87-102`，`A/ui/theme/CircularRevealTheme.kt:59-70,83-107,138-161`。
- iOS 当前 `.systemGroupedBackground`、系统材质玻璃、默认 `.blue`、默认 theme=`system`，没有上述固定 palette/揭示动画，见 `I/Views/OriginalRootView.swift:42-43,159-180`、`I/Models/OriginalPreferences.swift:28-30,43`。
- Android 卡片所谓玻璃是颜色 alpha + 描边，没有对卡片后方做 native material blur。iOS `.ultraThinMaterial` 不能当作等价实现。

## 登录页逐组件映射

Android 主源 `A/ui/LoginScreen.kt:62-300`；iOS 对应 `I/Views/AccountView.swift:37-64`、`I/Models/AuthManager.swift:20-37,79-84`。

| Android 组件 / 源码 | 精确视觉与可见文字 | 当前 iOS 不匹配 |
|---|---|---|
| 全屏底层 `LoginScreen.kt:103-131` | 垂直渐变 `#1A73E8 → #0D47A1 → #051D40`；左上圆 280，offset(-120,-80)，白 alpha .04；右下圆 180，offset(+60,+60)，白 alpha .06 | Form 底，无渐变、装饰圆 |
| 内容与入场 `66-67,101,133-142` | 纵向可滚动 Column；scale .8→1，tween 400ms；整体 y=-50；padding 左右28、顶90、底28；水平居中、顶部排列 | 无此入场/偏移/布局 |
| 品牌区 `143-152` | `app_logo` 80×80、圆角18；距下16；「淋 浴」30 Bold 白；「Hualala · 校园热水」13 白 alpha .55；距下20 | 完全缺失；已核实 `OriginalLogo` 与 app_logo 二进制 SHA256 相同，可复用原图 |
| 登录卡 `154-167` | 满可用宽，白色固定不随深色；圆角24、shadowElevation12；内容 padding28；「欢迎回来」22 Bold `#1A1A1A`；「请使用校园账号登录」13 Gray，顶4底20 | 系统分组表单 |
| 模式切换 `169-184` | 居中 TextButton，底距16，13 `#1A73E8`；短信模式显示「密码登录」，密码模式显示「验证码登录」；说明12 Gray、底12：短信「未注册的手机号将自动创建账号」，密码「未设置密码？请使用手机号验证码登录」 | Toggle「使用密码登录」，缺两条说明 |
| 手机号 `186-198` | OutlinedTextField 满宽、圆角14、单行；label「手机号」；左 Material Phone 蓝；非空右 TextButton「✕」Gray 清空；Phone 键盘；下距14 | 裸 TextField，无图标/边框/清空 |
| 短信行 `200-230` | 验证码 field weight1，label「验证码」、Number 键盘、圆角14；右间距12；发送 Button 固定宽84、圆角14、水平内容 padding4；正常蓝 `#1A73E8`、禁用 `#90CAF9`；白13单行「发送」或「60s」倒计时 | label「短信验证码」；独立「发送验证码」行；无固定按钮/倒计时 |
| 密码 `232-245` | OutlinedTextField，label「密码」，左 Material Lock 蓝，非空右清空「✕」Gray，密码遮盖、Password 键盘、圆角14 | SecureField 无原框/图标/清空 |
| 登录按钮 `246-264` | 前距24；满宽高52、圆角14；正常蓝、禁用浅蓝；默认 elevation4；「登 录」17 Bold；loading 时白22圆进度、stroke2，替代文字 | 普通「登录」行；loading 位于操作反馈 Section |
| 错误面板 `266-275` | 前距16、圆角8、底 `#FFEBEE`；消息 padding12、13 `#C62828`、居中 | 通用 `activity`，错误加「操作失败：」放表单末尾 |
| 固定输入配色 `292-300` | focused border/label/cursor `#1A73E8`；unfocused border `#BFC7D5`、label `#6B7280`；文字始终 `#1A1A1A` | 系统主题输入配色 |

登录行为完整状态约束（`A/ui/LoginViewModel.kt:15-141`、`LoginSecretPolicy.kt:3-15`）：

- 初始手机号/密码/验证码空；默认短信模式；loading/sending=false，countdown=0、error=null。
- 登录：空 phone 静默返回；phone 长度非11 →「请输入 11 位手机号」；相应 secret 空则返回。**按钮只根据 isLoading 禁用**，不能把 iOS 当前空字段也置灰的逻辑直接照搬。
- 短信发送：phone空、发送中、countdown>0直接返回；长度非11同上。合法后立即开始60秒倒计时，每1000ms减1，先于网络完成；成功 smsSent=true（页面无成功标记）；失败显示服务端原因或「验证码发送失败」，取消倒计时回0。按钮启用条件 `!isSendingCode && countdown==0`。
- 切换模式：翻转模式、清error、清password与smsCode；保留 phone，未取消 countdown。iOS 当前 Toggle 不清 secret/error。
- 请求开始置loading并清error；无论成功失败，password请求 finally 清password，sms请求 finally清smsCode。iOS `@State` 两类 secret 登录失败后仍保留，需修正。
- 密码错误网络映射：host/no address/unreachable →「网络连接失败，请检查网络设置」；timeout/timed out→「连接超时，请检查网络后重试」；其他服务端文案或「登录失败」。短信登录失败直接异常文案或「登录失败」。
- 成功触发 `onLoginSuccess(phone)` 后 resetResult；根容器 `beginSession()` 清旧挤号状态，设置phone，进入首页tab0（`A/MainActivity.kt:184-191`）。iOS page 位于持久根 `@State`，登录成功没有显式重置page到0（`OriginalRootView.swift:7,13-21`）。
- Android Autofill username/password/smsOtp 三节点，记录窗口bounds、焦点请求、离页移除（`LoginScreen.kt:54-58,73-91`）。iOS phone目前 `.telephoneNumber`；应兼容用户名/密码管理器流程，保留短信 `.oneTimeCode`。

## 首页逐组件映射

主源 `A/ui/MainScreen.kt:60-725`；对应 `I/Views/OriginalRootView.swift:71-149`。

| 组件 / 源码 | Android视觉、文字与状态 | iOS 当前差异 |
|---|---|---|
| 容器 `167-190,307-320` | 首次 visible false→true fadeIn；Scaffold背景纯色或透明；LazyColumn横向20、item间16；首Spacer8、末Spacer110；下拉指示器 SolidSurface+Accent | VStack间18、padding20末12；底栏占 VStack 布局高度；系统 refreshable，未匹配固定指示器 |
| 页头 `192-220` | 左「淋浴」30 Bold TextPrimary；下「Hualala」14 TextSecondary；右扫码+刷新两个40圆，Card底，icon20 TextPrimary，二者间8 | 左多了36 logo；副标题变学校/趣智校园；仅扫码、无右刷新 |
| 活动设备区 `223-238,536-583` | 有activeOrders显示「使用中的设备」18 Bold，逐单卡；否则lastMac非空才显示「上次使用设备」18 Bold及上次卡 | 标题变「使用中」；卡片有计时和结束按钮；active和last同时显示（Android互斥） |
| ActiveOrderCard `537-580` | 满宽、圆角22、ActiveBg、border .8 Border、elevation0；Row padding16；头像48圆角14；🪥橙`#FFCC80`、饮水绿`#10B981`、其他Accent；glyph图26/emoji22；间14；名称SemiBold单行尾部优先；下距4；「使用中」11 Warning，badge圆角6、横6竖2；间8「点击恢复订单」12 Secondary；右「恢复」按钮圆角16 Accent | 纵向20 padding、圆角24材质；没有状态badge、彩底glyph与恢复按钮；直接结束/继续结算改变原交互 |
| LastDeviceCard `586-625` | 与上同尺寸但Card底；默认淋浴头像**固定**`#2563EB`，不跟提色；名称SemiBold；下4；「MAC: {mac}」12 Secondary；两个文本都TailEllipsis；右「开始」圆角16 Accent | 「上次使用」、大emoji无彩底、typeLabel替代MAC、「快速开始」 |
| 附近标题 `240-249` | Row顶padding4，左「附近设备」18 Bold；右 `{余额标题} ¥{数字}` 或 `{余额标题} ¥ —`，14 Secondary | 余额改成页顶大额独立卡（34 rounded Bold+水滴），标题右改成扫描/停止；原版没有此大卡 |
| 寝室筛选 `252-269` | 「🏠 已筛选：{roomKey}」13 Medium Accent；间8；「取消筛选」12 Secondary，按钮contentPadding0；取消即时更新并toast「已取消寝室筛选」 | 仅building.2 Label原boundRoom、caption Secondary；没有取消入口 |
| 扫描状态 `272-289` | 扫描时左14圆进度stroke2 Accent、间8「扫描中...」13 Secondary；右强/中/弱legend，各点8，字间3，组间8，字11 Secondary | 只有标题旁系统spinner/停止，缺原状态行和图例 |
| 权限卡 `292-294,633-665` | 满宽圆角22 Card、border .8、elevation0；padding20；首「📶 开启扫描，发现附近设备」SemiBold（旧Android为🔍）；下6；说明12；下12；满宽按钮圆角12 Accent「授予权限并扫描」；下6；「也可以直接用右上角 📷 扫码绑定设备，无需任何权限」11 Secondary | iOS空列表统一天线+引导卡，权限未分专门状态；平台权限说明须适配iOS，但保留原布局和明确授权入口 |
| 权限说明原文 `647-653` | Android12+「需要「附近的设备」权限才能扫描附近的热水器。」；≤11「Android 11 及以下系统规定：扫描蓝牙设备必须授予定位权限。授权后仅用于发现附近的热水器。」 | 不应原样复制Android权限名到iOS；业务文案与OS权限适配需单独管理 |
| 空态 `295-304` | 仅有权限且非扫描时显示；满宽Box padding32居中 Secondary：「未找到寝室内的热水器」或「未发现热水器」 | 所有空态都展示大卡+「靠近水表后扫描附近设备」+状态+开始扫描 |
| DeviceCard `668-715` | 满宽圆角22，Card/border.8/elevation0，Row padding16；头像48/圆角14、glyph图26或emoji22；间14；名称SemiBold Primary（此处普通Text，**允许换行**，别误套上次卡缩放）；下6「信号强度: {rssi} dBm」13，>=-70 Success，>=-85 Warning，其余Danger；下2 MAC12 Secondary；右 Material KeyboardArrowRight Secondary | 仅emoji无彩底，无MAC；信号改强/中/弱且阈值>-65/>-80；信号颜色统一secondary；系统chevron不是原图 |
| 卡片反馈 `676-697` | 按下scale .97、释放1，spring stiffness700；圆角clip涟漪，Accent alpha.25 | `.plain` Button无缩放、无原涟漪 |

首页加载与导航约束：

- 进入刷新wallet、bills、campusBalance、schoolName、unpaid、initManagers；已授权才静默扫描，未授权不立刻弹权限。下拉刷新同时pullRefresh+扫描权限流，1000ms后隐藏指示器；页头刷新同请求但没有pullRefreshing状态。`A/ui/MainScreen.kt:102-133,212-217`。
- 过滤以原始设备名提取roomKey，boundRoom需可观察状态，清除后即时重排。房间关键词是去类型前后缀、尾房字、分隔符统一的小写完整键，兼容短键以“-键”结尾，防止320误匹配1320；格式化显示名不参与房间判断。`A/model/DeviceModels.kt:139-249`；iOS同类format规则已实现于 `I/Models/OriginalAppModels.swift:204-224`。
- 余额优先一卡通，其次钱包，再本地手填减填写时刻后消费。无真实余额时需要账单到位才能展示估算，防止先闪原始手填数字。标题「一卡通余额 / 趣智校园余额 / 余额」。金额保留3小数、末位0时减为2位。`A/ui/MainScreen.kt:149-165,247`、`A/data/BalanceEstimator.kt:42-65,92-115`、`A/utils/MoneyFormat.kt:18-24`。iOS金额规则与优先级大体已有，但首页位置/字体/符号空格不一致。
- 点击附近卡只查设备信息并弹详情；扫码结果查SN、保存last、弹详情、刷新归属，停止扫描避免列表跳。v3.1.0 `MainViewModel.kt:428` 左右的scanBind对应HEAD `428-461`；官方 fetchDeviceInfo 缓存命中直弹、非命中查接口，只有特定网络异常toast，没有HEAD新增的「服务端没有这台设备的记录」和其他获取失败toast。iOS choose会连接BLE、读状态帧、强制记Bluetooth、关联后额外message=设备名（`I/Models/OriginalAppModel.swift:193-206`），可见等待与行为不等价。
- Android正在使用时在主页位置替换为ShowerScreen，导航隐藏；收起恢复主页但设备运行。iOS通过fullScreenCover，需按统一使用页任务协调。`A/ui/MainScreen.kt:172-183`、`A/MainActivity.kt:223-228`；`I/Views/OriginalRootView.swift:47-49`。

## 底部悬浮胶囊导航

来源 `A/ui/FloatingPillNavBar.kt:45-180`；iOS `I/Views/OriginalRootView.swift:24-29,63-69`。

- 外层满宽、安全区navigation padding，底22、左右24；居中固定宽260（不是按屏幕两边55推导宽度）。Surface圆角28；Light `#D8FFFFFF`、Dark `#B81A202C`；1dp边框Light `#18000000`/Dark `#28FFFFFF`；shadow10，tonal0。
- 内padding4，故胶囊内容宽252、三等分每项84；高亮块高42、宽itemWidth、圆角22、底Accent、shadow2。实际总高50；滑块offset=itemWidth×tab，spring damping .72 stiffness380。
- 三项严格为「首页」「账单」「我的」，图标分别Material Home、原 `ic_receipt_long.xml`、Material Person。每项横向 icon16 + gap4 + 字11 Medium，项高42、圆角22。iOS当前第二项「钱包」+wallet图标、纵向图文，须全部对齐。
- 高亮内容颜色按**Accent本身**luminance>.5取`#0F172A`，否则白；未选Light `#64748B`/Dark `#94A3B8`。内容颜色200ms tween；选中scale1.04/未选1，spring .72 stiffness400。切不同tab才发LongPress haptic；无涟漪、无按压缩放。iOS目前selected字体Accent、底Accent .12、系统材质、无haptic。
- 主页面切换前进从右进入，退出向左，反向相反；整页水平满宽滑移+fade；offset spring damping .78 stiffness420，fade spring stiffness420。`A/MainActivity.kt:194-212`。iOS仅按钮matchedGeometry和page切换，没有整页弹簧过渡。
- isShowering或userSettingsVisible时不显示。iOS当前导航永远作为主VStack末项，设置页面是否隐藏需与个人页任务协调。`A/MainActivity.kt:223-228`。

## 设备详情与启动反馈弹窗

主源 `A/ui/DeviceDetailDialog.kt:18-114`，`A/ui/MainScreen.kt:326-533`；iOS `I/Views/OriginalRootView.swift:45-61,183-242`。

| 状态 | Android要求 | iOS差异 |
|---|---|---|
| 设备详情 | Material3 AlertDialog；title居中Column，Row emoji22+gap6+类型22 Bold；类型「饮水（热水）/饮水（冷水）/洗漱/沐浴」；下一行displayName15 Medium Gray；**标题保留emoji，不能换白DeviceGlyph** | 当前medium/large sheet+Form；顶部emoji50、标题「设备详情」、displayName title3 |
| 详情字段 | 「类型」「SN 码」「MAC 地址」「预扣金额」「状态」；行满宽SpaceBetween竖padding4，两边bodyMedium、label Bold；类型值为饮水机/洗手台/热水器；状态活动→使用中，否则空闲；金额MoneyFormat.withSymbol | iOS缺MAC、状态、只放设备编号；类型用typeLabel，金额空缺按0，原文与格式不同 |
| BLE说明 | needsBluetoothControl时前距10；「此设备通过手机蓝牙直连控制：开启后请留在设备旁，走远会断开连接、无法关闭。」13 Secondary、行高18 | iOS总有「蓝牙直连设备」Toggle和技术说明；原版此处没有Toggle |
| 确认/取消 | 未活动→「开始接水」(饮水)/「开始使用」；活动自己→「恢复使用」；活动他人→「他人使用中」禁用；可用按钮Accent，否则Secondary；点击可用先onConfirm再onDismiss；取消TextButton「取消」；背景点击可关闭 | iOS活动设备给「结束使用」，没有归属禁用，关闭Toolbar替代取消 |
| 开启中 | `MainScreen.kt:423-444`不可dismiss AlertDialog；title「正在开启热水器...」Bold居中；Row居中24进度stroke2.5 Accent+gap12；文字bleProgress或「正在确认设备是否开启，请稍候」Secondary；无操作按钮 | iOS只在列表末显示「正在处理…」，没有阻断开启确认弹窗/BLE逐阶段进度 |
| 开阀失败 | `337-394` AlertDialog，title「开阀失败」或「开阀失败 · 有未扣账单」Bold；message14 Primary；仅SERVER_REJECTED展示deductibleBills；12间距后「检测到 N 笔没扣成功的账单：」13 Medium Warning；gap6；每笔「· ¥{原字符串或?}   {时间前16}」12 Secondary；gap8；「账户有欠费时服务端会拒绝开阀」11 Secondary | iOS变sheet+List，行/颜色/排版不同，原文「未扣账单」不同 |
| 失败操作 | 有账单Warning Button「立即补扣」，无账单TextButton「知道了」；始终有「关闭」；dismiss清错误。点立即补扣只是打开二次确认 | iOS sheet标题栏关闭；无无账单「知道了」 |
| 改BLE重试 | `452-483` AlertDialog title「要用蓝牙方式开启吗？」Bold居中；说明Secondary行20，含设备名、手机必须待设备旁、用官方「趣智校园」辨别的完整段落；满宽Button「用蓝牙开启」，TextButton「取消」；可dismiss | iOS confirmationDialog「该设备离线或需要手机蓝牙直连」+「使用蓝牙直连重试」，缺完整说明及弹窗视觉 |
| 自动关闭 | `487-533`不可dismiss；title「⚠️ 热水器已自动关闭」Bold居中；居中设备行「🚿 」16+设备名Medium Primary；gap6；「⏱ 已用 XmYs/ Ys」Secondary；gap12；loading 14进度stroke2+gap6「结算中...」；完成为Bold Accent「本次消费：¥…」或「消费金额稍后可在账单中查看」；满宽Button「确 认」 | iOS系统Alert「热水器已自动关闭」，无loading/实际金额分支、按钮「知道了」；文字「使用时长：」不同 |

BLE重试完整原文（`A/ui/MainScreen.kt:465-469`）：

> 「{displayName}」无法通过云端开启。\n\n如果这台设备需要手机蓝牙直连（开启时必须待在设备旁边），可以改用蓝牙方式。\n\n不确定的话：用官方「趣智校园」试一下——需要站到设备旁才能开的就是这一类。

## DeductConfirmDialog（首页与账单共用）

来源 `A/ui/DeductConfirmDialog.kt:37-78`；iOS对照 `OriginalRootView.swift:231-239,283-286,351-358`。

- Material3 AlertDialog可dismiss；标题「确认扣款」Bold。
- 内容Column：「将从校园卡中扣除：」13 Secondary →gap8→ 金额22 Bold Danger或「金额无法识别」22 Bold Secondary →gap6→ detail12 Secondary（首页为「共 N 笔」，账单为时间）→gap12→说明11。
- 金额已知说明「余额不足时会扣款失败」，Secondary；未知说明「服务端返回的金额格式不对，无法确认将扣多少钱。请到「钱包」页逐笔核对后再操作。」，Warning。
- 确认按钮「确认扣款」Warning，**amount为null禁用**；取消TextButton「取消」。不能把null金额转0，也不能让用户确认按服务端金额扣。
- 首页只有所有金额字符串均可parse时total才可确认；错误变化复位confirming；确认后先关闭二次确认、清showerError，再deductAllUnpaid。结果toast严格分为：未发出「没有可补扣的账单，或正在处理另一笔代扣」；全部未知「补扣结果未知，请下拉刷新确认后再操作」；部分未知「成功 X 笔、失败 Y 笔、Z 笔结果未知」；全成功「补扣成功，再试一次开阀」；全失败服务端首原因或「补扣失败，请到「钱包」页重试」；部分成功「成功 X 笔、失败 Y 笔」。`A/ui/MainScreen.kt:345-418`。
- iOS虽有服务端拒绝筛选与可空total（`I/Models/OriginalAppModels.swift:63-78`），但呈现与按钮禁用错误，结果文案也不完全相同（`I/Models/OriginalAppModel.swift:355-381`）。

## 全局会话弹窗

来源 `A/MainActivity.kt:239-282`；iOS `I/Models/AuthManager.swift:59-76`、`I/Models/OriginalAppModel.swift:174-187`。

- 挤号：不可dismiss；title「账号在别处登录」Bold居中满宽；正文「当前登录已失效。设备可能仍在用水，请重新登录核对，或立即使用官方客户端、联系人工处理。」居中onSurfaceVariant；满宽Button「确定」。点后logout(preserveActiveRecovery=true)、回登录。iOS心跳失败直接expireSession「登录状态已失效，请重新登录」，没有必须确认与保留使用恢复提示的原UI。
- 主动退出：按canLogoutVoluntarily(activeOrders)决定。可退title「确认退出」、正文「确定退出登录？」、确认「退出」error色、取消「取消」；不可退title「无法退出」、正文「设备使用中，无法退出」、仅「返回」primary色；可dismiss。iOSAccountView退出按钮直接logout并只看transactionInProgress；个人页另有入口需共用原判断，不能仅禁止请求进行中。
- 通知/小组件入口navRequest可在onCreate与onNewIntent接收；未登录先保留，登录后再消费tab和showShower；tab0首页/tab1账单/tab2我的。`A/MainActivity.kt:52-61,114-122,289-302`。iOS URL处理在model不含page更新，`I/Models/OriginalAppModel.swift:445-460`，需要补齐目标tab协调。

## DeviceGlyph 与 TailEllipsisText

- `A/ui/DeviceGlyph.kt:29-62`：🚿→`ic_device_shower.xml`、🪥→`ic_device_sink.xml`，固定白tint；其余饮水emoji原样彩色显示。首页调用emoji22sp/icon26dp；不要用SF Symbols或全改emoji替代。两个原vector均24dp/viewport24，内容归一到20×20：shower group scale .038865、translate(2.3804,3.3051)，sink scale .714272、translate(.5716,.5716)，具体path必须直接转换原资源；iOS当前无对应原图标资源。
- `A/ui/TailEllipsisText.kt:17-97`：单行，无softWrap；先原字号，失败依次×.92缩小直到不低于原.78；仍放不下使用原.78并二分寻找最长后缀，前置「…」；按LocalTextStyle merge测量，最终Clip。默认字号从ambient取，否则14。用于活动订单名、上次设备名/MAC、toast；**不用于附近DeviceCard名称**。iOS当前这些位置无minScale/head truncation，容易换行或截掉房号。

## LinYuToast

来源 `A/ui/LinYuToast.kt:26-96`；iOS `I/Views/OriginalRootView.swift:32-39`。

- 全屏Box TopCenter；外padding top60、左右24；shadow8、圆角16、底`#1F2937`；内横20竖16。Row居中、间距12；左原logo32；右TailEllipsis14 Medium白、weight1 fill=false，保持一行保留尾部。
- 非空message立即visible；2500ms后hidden，再300ms onDismiss清消息。空/null立即隐藏；message切换重启协程。enter向下（初始offset=-自身高）slide+fade；exit向上slide+fade，使用Compose默认动画规格。
- iOS当前是底部85、rounded18、系统regularMaterial、没有logo、subheadline、多行未受限、4秒后直接清、move(bottom)+opacity，全部不匹配。

## 扫码页完整映射

Android `A/QrScanActivity.kt:114-633`；iOS `I/Views/OriginalScannerView.swift:6-100`。

| 组件/状态 | Android精确要求 | iOS差异 |
|---|---|---|
| 页面与导航 | Activity全屏黑，camera Preview FILL_CENTER，覆盖安全区，状态/导航透明且浅色系统图标；不随主题/提色。页头安全区下横4竖4；Material ArrowBack白；「扫描二维码」17 Medium白 | `.sheet`呈现；文字按钮返回、标题「扫一扫」居中；安全区/导航形式不符 |
| 扫描框 | side=min(width×.72,280dp)，left=(width-side)/2，top=height×.5-side×.62；仅四角，每角长度side×.16，白stroke3 Round | 260×260完整圆角24边框，居中；无原框位置比例 |
| 遮罩 | 框外四块黑 alpha.62，中间相机无遮罩 | 无框外遮罩 |
| 扫动光带 | progress0→1、2200ms Linear、无限Reverse；beamY=top+side×progress；竖渐变透明→`#FFC53D` alpha.85→透明；总高14、左右缩4 | 缺失 |
| 底提示 | 安全区上bottom24；提示13、正常白alpha.75「将二维码放入框内，自动扫描」；错误暖黄`#FFC53D`；下距18 | 提示「将水表二维码放入框内」，subheadline、材质Capsule，中间显示 |
| 底按钮 | Row整宽SpaceEvenly；顺序相册、手电筒、取消扫码；每个圆52、白alpha.10、1边白alpha.28，图22；取消用原qr_code_scanner图 | 顺序手电筒、相册；有文本Label、gap70、padding32；缺取消按钮 |
| 手电筒亮 | 52圆暖黄实底、无边；外64圆暖黄alpha.22光晕；图使用实心`ic_flashlight_on`深色`#1A1206`；灭时原白描边`ic_flashlight` | SF Symbol切换，无原底色/光晕；无hasTorch UI条件 |
| 无闪光灯 | 整个按钮隐藏，52×52占位保持两侧位置 | iOS仍显示能切状态但无效果的手电筒 |
| 无权限/启动失败 | 不显示扫描框/底按钮；黑底安全区内居中Column、横36；title18 Bold白、gap10、desc13白.65、gap16；actions Row gap8，TextButton14暖黄 | iOS只把错误写入提示，仍显示相机框和按钮；无专用状态/重试/设置入口 |

扫码行为与精确状态文字：

- 不自动请求相机权限；初始未授权展示「需要相机权限」+「扫码要用到相机。权限只用于识别二维码，不会拍照上传」，按钮「授予权限」「返回」。拒绝后desc「权限被拒绝了。可以点下面的「授予权限」再试一次，或者去系统设置里打开」，增加「去设置」；hint「没有相机权限就没法扫码」。启动失败title「相机启动失败」，desc「可能是相机被其他应用占用，或者设备不支持。稍后再试一次，或者重启一下手机」，按钮「重试」「返回」。`QrScanActivity.kt:319-333,423-459`。iOS目前makeUIView即requestAccess，拒绝只有「请在系统设置中允许相机权限」，部分canAddInput/output失败还静默返回（`OriginalScannerView.swift:67-84`）。
- 成功识别必须字符串contains `KLCXKJ-Water`（case-insensitive）；取最后逗号字段trim、删冒号、uppercase、严格12位HEX。只返回一次，haptic CONFIRM/旧版VIRTUAL_KEY；返回sn并关闭。`QrScanActivity.kt:127-138,194-215`。iOS解析已等价（`OriginalAppModels.swift:225-235`）、hasResult防重已在，但无成功haptic。
- 相册走系统照片选择器，不申请存储权限。图片读取离主线程；无匹配「这张图片里没有找到设备二维码」；识别失败「图片识别失败，换一张试试」；读图失败「这张图片读不出来，换一张试试」；hint在2600ms后清除。`QrScanActivity.kt:280-292,335-367`。iOS只实现无匹配消息且不自动清，读失败无可见提示。
- 退出关灯、解绑相机、关闭scanner；iOS stop关灯已有。Android无相机权限时相册按钮也不显示，不能自行把相册移入权限Notice状态视为忠实复刻。
- 主页面接收RESULT_OK缺SN提示「未识别到有效二维码」；RESULT_CANCELED若带error也toast。`A/ui/MainScreen.kt:82-99`。

## 原始资源与字体约束

- 登录/toast用 `AR/drawable-nodpi/app_logo.png`，已实际查看为白圆角底黑色淋浴人物剪影；与iOS `OriginalLogo.imageset/image.png`相同SHA256：`623e85254948075d086194447d0b4949d7941e624e0cce82fb80cada645002f0`。
- 原xml vector（已完整读path）：`AR/drawable/ic_receipt_long.xml`、`ic_qr_code_scanner.xml`、`ic_photo_library.xml`、`ic_flashlight.xml`、`ic_flashlight_on.xml`、`ic_device_shower.xml`、`ic_device_sink.xml`。前五均24dp/viewport24。Receipt/QR path本身黑，由调用处tint；photo白；torch灭白stroke1.8、Round joins/caps透明填充，亮相同path深色实填。应转成原矢量等价资源，避免替换图形轮廓。
- Compose `MaterialTheme(colorScheme=scheme,content=...)`未传Typography；字号未显式指定的body/按钮需按APK统一测量。iOS默认 `.headline/.caption/.title`等不构成Android字体大小/行高等价。Emoji跨系统字形也会不同；照片式参考需要用原系统渲染对照，但不能任意用新符号改风格。

## 完整阅读清单与边界

以下文本文件均逐行完整阅读（非仅rg命中）：

Android：

- `A/ui/LoginScreen.kt`（300行）、`LoginViewModel.kt`、`LoginSecretPolicy.kt`。
- `A/ui/MainScreen.kt`（725行）、`FloatingPillNavBar.kt`、`DeviceDetailDialog.kt`、`DeductConfirmDialog.kt`、`DeviceGlyph.kt`、`TailEllipsisText.kt`、`LinYuToast.kt`。
- `A/QrScanActivity.kt`（633行）、`A/MainActivity.kt`（320行）。
- `A/ui/theme/Theme.kt`、`A/ui/theme/CircularRevealTheme.kt`、`A/ui/AppBackgroundLayer.kt`。
- `A/model/DeviceModels.kt`、`A/model/LoginModels.kt`、`A/utils/MoneyFormat.kt`、`A/utils/ScanPermission.kt`、`A/utils/BackgroundState.kt`、`A/utils/BackgroundManager.kt`、`A/data/BalanceEstimator.kt`、`A/data/AuthRepository.kt`。
- `AR/values/themes.xml`、`AR/values-night/themes.xml`、`AR/values/strings.xml`、`AR/values/colors.xml`、上述7个drawable XML、`app/build.gradle.kts`、`gradle/libs.versions.toml`。

iOS：

- `I/Views/AccountView.swift`（74行）、`I/Views/OriginalScannerView.swift`（100行）、`I/Views/OriginalRootView.swift`（370行，包含详情、失败、使用、账单等内嵌组件）。
- `I/Models/AuthManager.swift`（86行）、`OriginalAppModels.swift`（302行）、`OriginalAppModel.swift`（468行）、`OriginalPreferences.swift`（103行）、`OriginalBackgroundPalette.swift`（74行）、`OriginalPlatformServices.swift`（57行）。

额外按需阅读（**非完整通读**）：HEAD `A/ui/MainViewModel.kt:76-100,388-670,1480-1524`；`git diff v3.1.0 HEAD -- MainViewModel.kt`；`git show v3.1.0:.../MainViewModel.kt` 的设备查询与归属段。使用页具体视觉/账单主页面/个人设置的独立Android组件由其他盘点任务负责，本文件只记录其根路由和本任务内共享弹窗。

二进制资源已视觉检查：Android `app_logo.png`、iOS `OriginalHome.imageset/image.png`；logo另作SHA256一致性检查。未启动Android/iOS运行时、未声称做过像素差比对。仍需在目标APK与iOS实际设备上核验字体fallback、默认Material3 AlertDialog几何、系统安全区、输入法与动画表现。
