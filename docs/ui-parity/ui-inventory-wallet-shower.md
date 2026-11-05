# LinYu Android → iOS：钱包、账单、用水页、桌面组件只读盘点

日期：2026-11-05。目标是逐项还原原版，以下参数是原版事实或明确注明的 iOS 实现映射，不是重新设计方案。没有修改产品代码、测试或提交。

## 0. 版本、定位规则和证据边界

- Android 工作树 HEAD：`ff5f8befb2416a21955927c54677e26740a4002a`（未发布 3.1.1）。已核对官方 `v3.1.0` 的实际commit：`a650066a9624681a0e3404063219435d3717fa98`；`761ae9b51bb0168b5a4de63a91f5168328107234`是annotated tag对象，不是源码commit。用户已确认以官方v3.1.0作为复刻基准。
- `git diff v3.1.0 HEAD --` 核对本盘点的 WalletScreen、SpendingTrendCard、TrendDisplayPolicy、ShowerScreen、Theme、SpendingAnalytics、BillDateParser、BalanceEstimator、DeviceModels、LoginModels、背景辅助、MoneyFormat、所有布局和 drawable：这些文件无差异。WidgetRenderer / LinYuWidgetProvider 的差别列在第 7 节，不能把未发布修复误称为官方 APK 行为。
- iOS 基线 HEAD：`a2527e5968af751fd0cf4477a18f186bcdefd3ea`。以下 iOS 行号均对应此基线。
- 文中 `A/` = `D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/`；`I/` = `D:/User/Documents/move_to_ios/work/livecontainer-cloud/`。`路径:行号` 均可据此展开，所有参数来自实际阅读；未声称进行 APK / iPhone 逐像素验收。
- Android Compose 的 dp 对应 iOS 布局 pt；sp 需用匹配字号及字体度量验证，不能以 SwiftUI `.title` / `.caption` 的平台默认值替代精确数值。原版没有定义字体文件，使用系统字体；中文/emoji 跨平台字形是最终截图验收项目。

## 1. 共用主题、背景、金额与数据规则

来源：[Theme.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/theme/Theme.kt:16)、[AppBackgroundLayer.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/AppBackgroundLayer.kt:28)。

| Token | Light ARGB | Dark ARGB |
|---|---|---|
| Background | `FFF1F5F9` | `FF0E131D` |
| Card | `B8FFFFFF`（184/255） | `BF1D232E`（191/255） |
| SolidSurface | `FFFFFFFF` | `FF161B22` |
| Primary | `FF0D1117` | `FFE6EDF3` |
| Accent | `FF2563EB` | `FF58A6FF` |
| TextPrimary | `FF111827` | `FFE6EDF3` |
| TextSecondary | `FF6B7280` | `FF8B949E` |
| Success | `FF22C55E` | `FF3FB950` |
| Warning | `FFF59E0B` | `FFD29922` |
| Danger | `FFEF4444` | `FFF85149` |
| Border | `14000000` | `14FFFFFF` |
| ActiveBg | `FFFFF7ED` | `FF1B1F23` |
| SurfaceVariant | `FFF0F0F0` | `FF21262D` |

原版玻璃卡片是**带固定 alpha 的填色 + 描边**，不是系统 Material 模糊；默认 elevation 为 0。弹窗 M3 surface 为 SolidSurface，dark onPrimary 为 `FF062E6F`，light 为白色。home 背景提取色只替换全局 Accent，既不改变深浅模式，也不以 shower 提取色替换强调色（Theme.kt:99）。

背景两作用域：home 用于首页/钱包/我的；shower 用于使用页。`BgConfig.enabled` 默认为 false；opacity/blur/brightness 默认为 1/0/1，独立持久化。图片 `ContentScale.Crop` 全屏；先 alpha，blur(dp)，RGB 乘 brightness，alpha 不乘亮度。保存 JPEG quality 95，最大边解码采样阈值 2560；文件更新时间+作用域缓存，换图增加版本。主题色提取缩至 48×48，RGB 每 32 量化，过滤 S≤.15、V≤.20 或 V≥.95，再取频数最多；S clamp .35–.75、V clamp .45–.85。（A/java/com/hualala/linyu/utils/BackgroundState.kt:8、BackgroundManager.kt:25；AppBackgroundLayer.kt:38）

iOS 当前 `OriginalGlassCard` 一律 padding 20、圆角24、`.ultraThinMaterial`、白 .28 描边 .8；`OriginalBackground` 一律 systemGroupedBackground+OriginalHome/OriginalShower fallback asset，没有 Android 的 enabled 状态或使用页默认渐变（I/LinYuIOS/Views/OriginalRootView.swift:159、169）。需按各组件显式填色/半径/内边距映射。iOS 亮度矩阵、48×48提色与2560/JPEG .95导入已存在，可复用；默认 accent 仍为 `.blue`，主题默认 `system`，不能视为已对齐 Android 的明暗 token。（I/LinYuIOS/Models/OriginalPreferences.swift:27、44；OriginalBackgroundPalette.swift:9、21、49）

金额统一 `%.3f`，若末字符为 0，只去掉**一个**0，因此 5→`5.00`，.025→`0.025`，10.150→`10.15`；货币前缀和空格由各 UI 原文决定。不要把 MoneyFormat.kt 注释中的 `5.0` 示例当实际结果。厘→元除1000。iOS `OriginalFormatting.money` 实现已对应且固定 POSIX locale。（A/java/com/hualala/linyu/utils/MoneyFormat.kt:22；I/LinYuIOS/Models/OriginalAppModels.swift:240）

余额来源优先级：校园卡 `amount` → 趣智校园钱包 `money` → 本地「手填初始余额−填入时刻之后消费」。标题依次为「一卡通余额」「趣智校园余额」「余额」。本地估算按严格 `billTime > manualBalanceTime`，允许负余额，未填写初始金额内部结果0。**钱包页**实际使用 `displayBalance?.let { ¥ ... }`，与 BalanceEstimator.format 不同：已加载账单但从未手填时可能显示 `¥ 0.00`；桌面 format 会显示 `¥ —`。此源代码不一致应记录，不应偷偷修正后称完全一致。钱包和首页估算只吃最近20笔，趋势吃三个月 billHistory。（A/java/com/hualala/linyu/data/BalanceEstimator.kt:43、67、100、120；WalletScreen.kt:73）

## 2. 钱包页精确结构

来源：[WalletScreen.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/WalletScreen.kt:41)。顺序不能移动：余额来源标题 → 余额卡 → 可选趋势卡 → 账单标题和副标题 → 列表/加载/空状态。

| 层级 | Android 参数、文案和状态 | iOS 映射及现有差异 |
|---|---|---|
| 页面 | fullSize Box + statusBarsPadding；内部全屏可下拉、verticalScroll；padding20；底部额外100 | `OriginalWalletView` ScrollView保留，按安全区还原；当前VStack统一spacing18，导航另占高度，缺100底部间隔 |
| 标题 | `BalanceEstimator.title()`；22sp Bold primary；下间16 | 当前「钱包」largeTitle；替换为来源标题和22 |
| 余额卡 | 全宽，圆角22，Card，Border .8，零阴影，内24 | 当前OriginalGlassCard圆角24/内20/material均不符 |
| 卡首行 | 横向SpaceBetween、垂直居中；「账户余额 (元)」14 secondary；无真实余额时右侧「手动填写」13 accent；文本点击区域圆角6，horizontal6/vertical4 | 当前把来源标题放卡内，丢失固定账户标签；已有手填入口但判据需基于任一真实余额 |
| 数字 | 首行下4；`¥ ${formatMoney(balance)}` 或 `¥ —`；36 Bold primary | 当前38 rounded，间12；字形/字号/位置需还原 |
| 来源说明 | 数字下8；11 secondary。campus非空：「来自校园卡账户的实时余额」；wallet真实：「来自趣智校园账户的实时余额」；均空：「仅通过初始金额和账单进行估算，并非真实余额」 | 当前仅「来自账户的实时余额」/改写的估算文案，缺三分支 |
| 趋势 | 余额卡下24；trendEnabled=true显示；趋势后24；关闭时仅保留前一个24 | 现卡结构详第3节 |
| 账单标题 | 「账单」18 Bold primary；紧随「最近20次消费记录」12 secondary；下12 | 当前headline且缺副标题 |
| 加载 | `isLoadingBills` 时全宽padding24居中；24×24 Accent spinner，stroke2；覆盖列表即使有缓存 | 当前空数组即空文案，无账单专属加载态 |
| 空 | 非加载且空列表：「暂无账单数据」，secondary，top8 | 当前有文案，无top8/显式状态区分 |
| 列表 | Column行间8；最近20次billList | 当前每个OriginalGlassCard统一spacing18 |

首次进入触发 loadBills、loadCampusBalance、loadUnpaidBills；趋势开关进入时从Prefs读，页面重建后读取设置新值。下拉调用pullRefresh，指示器固定约1秒后隐藏（不绑定所有网络完成）。refresh不在钱包页触发扫描。初始估算必须等`billsLoaded`，任一真实余额可立即显示。（WalletScreen.kt:43、54、60、73；MainViewModel.kt:2104）

### 2.1 每条账单卡

`BillCard`（WalletScreen.kt:289）：全宽可点击卡，圆角14、Card、Border .8、无阴影；Row内14、SpaceBetween、垂直center。左Column weight1：第一行「`${deviceEmoji} ${displayDesc}`」14 Medium primary；下2为类型12（饮水机`FF10B981`，洗手台`FFFF9800`，其余Accent）；再下2为消费日期前16字符12 secondary。右Column末端对齐：`-¥ ${consumeMoney}`直接使用服务端金额字符串，16 Bold Danger。不能用重新四舍五入后的金额/Unicode减号替代原文。

只有服务端 unpaidConsumeDates 包含该条 **consumeDate** 才显示卡内「请求代扣」。金额下6；按钮高30、圆角10、水平内12/竖4、Warning填色、禁用TextSecondary .4；12白字。`deductingConsumeDate == date` 时只该行显示「扣款中…」并禁用，业务层另有全局锁。不能用账单字段猜是否未扣，也不按 orderId 匹配。（WalletScreen.kt:175、318；MainViewModel.kt:1824）

iOS 当前账单行是独立大emoji、无类型、完整日期、金额primary；点击开启远程详情sheet；额外插入「未扣账单」区域和「全部补扣」按钮。Android钱包没有该独立区域，也没有钱包页全部补扣入口；批量只在开阀失败弹窗。还原时需把服务端未扣列表匹配回各账单行。（I/OriginalRootView.swift:335–360）

### 2.2 钱包弹窗与确认

| 弹窗 | 原版内容/动作/状态 | 当前iOS差异 |
|---|---|---|
| 手动余额 | 标题「手动填写余额」Bold；正文「请输入账户当前余额」14 secondary；下4「此操作仅用于本地估算，不会修改账户真实余额」11 secondary；下12 OutlinedTextField，label「余额 (元)」，singleLine、Decimal、圆角12；仅接受空或`\d{0,9}(\.\d{0,2})?`；预填**当前显示余额**格式化结果，未得到显示余额时才用旧manual或0；「保存」写manual+当前毫秒并关闭；「取消」/外点只关闭 | 当前原生alert，直接绑定model.manualBalance，预填旧基准而非当前估算；无输入正则；取消前已改变内存文本；说明删改。需独立editValue草稿 |
| 单笔扣款 | `DeductConfirmDialog`标题「确认扣款」Bold；「将从校园卡中扣除：」13 secondary；下8金额`¥x.xx[x]`22 Bold Danger；下6消费日期12 secondary；下12「余额不足时会扣款失败」11 secondary；Warning确认「确认扣款」，取消「取消」；外点dismiss | 当前confirmationDialog标题/按钮/正文不同。金额无法解析时当前仍可确认实际扣款，不等效 |
| 金额未知 | 金额处「金额无法识别」22 Bold secondary；末说明为「服务端返回的金额格式不对，无法确认将扣多少钱。请到「钱包」页逐笔核对后再操作。」11 Warning；**确认按钮禁用** | 必须同样禁止确认，不能显示0/允许未知金额发请求 |
| 账单详情 | AlertDialog标题「账单详情」Bold；五行设备名/设备类型/消费金额/消费时间/订单号；每行全宽、上下4，左14 secondary，右14 Medium primary；金额`-¥ ${dto.consumeMoney}`；时间取19字符；订单号显示`dto.orderId`；「确定」关闭；外点关闭 | 当前NavigationStack+List sheet、设备/类型短标签、正金额、完整日期、orderNo优先；原版这里不请求billDetail，只用已选DTO |

来源：WalletScreen.kt:204、243、267、342；[DeductConfirmDialog.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/DeductConfirmDialog.kt:37)。注意原版`known = amount != null`，没有额外finite校验；规范复刻不能把代码事实与建议混淆。

扣款结果toast必须区分：「代扣成功」；明确失败用服务端reason或「代扣失败」；Unknown「结果未知，请下拉刷新确认后再操作」。Unknown重查服务端未扣列表，失败保持旧列表，不许直接假定失败。成功先去掉对应date再刷新未扣/账单。并发提示「正在处理另一笔代扣，请稍候」。（WalletScreen.kt:254；MainViewModel.kt:1876–2048）

## 3. 消费趋势卡（不能用默认Swift Charts外观替代）

来源：[SpendingTrendCard.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/SpendingTrendCard.kt:65)、[TrendDisplayPolicy.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/TrendDisplayPolicy.kt:3)。

- 默认范围LAST_7_DAYS、图型LINE、**collapsed=true**，三者都跨会话保留；Prefs非法枚举回退默认。切范围selectedIndex重置-1；切图型保留所选日；today在组件生命期remember，不是每秒换日。（PrefsHelper.kt:407–423；SpendingTrendCard.kt:72–93）
- 卡圆角18、描边.8、Card、无阴影、内18。标题「消费趋势」18 Bold primary；右40×40点击区，上/下箭头secondary，不画ripple；无整卡点击。折叠时仅这一标题行，不渲染指标/范围/图型/图表/标签。
- 展开：标题下18；三等分左对齐指标「总消费」「消费次数」「单次平均」，label11 secondary、下3 value15 SemiBold primary；金额MoneyFormat.withSymbol，次数`${count} 次`。下18进入内容。
- loading仅`isLoadingBills && !billsLoaded`，内容190高居中24 spinner/stroke2；指标仍绘制。非loading的控制行高32：左每日说明weight1，中范围weight1，间4，右图型weight1。左无选择「每日明细」12 normal secondary；选中为`M/d  ¥金额 · N次`12 Medium primary，单行ellipsis。
- 范围控件两等分「7天」「本月」，高30/圆角8，active填Accent .14、字Accent 11 Medium，inactive透明/secondary normal；图型控件「柱形」「折线」，同尺寸和选色、字11（没有额外Medium）。无系统segmented底槽、无ripple。
- Canvas高146；top10、bottom=height−10；max=max(全部金额,1)；点横向折线inset5，柱形inset=max(barWidth/2,5)，barWidth=(width/天数)*.58；单点x居中，多点均匀分布在inset至width−inset。Y=bottom−126*(amount/max)，没有Y轴、网格、图例、tooltip气泡。
- 柱：Accent alpha .72，圆角4，顶端点至baseline；折线：直线连接，宽2.5（不能catmullRom平滑），区域填Accent .10，从(0,bottom)经过所有点再到(width,bottom)。两种图都画**所有日点**：外Accent radius3、内Card radius1；选中外5/内2。
- 点选是tap x/width*(count−1)四舍五入并clamp，不按柱bar hit box，不要求拖动；点击后仅上方每日明细和点大小变化。
- 日期X标签M/d、10 secondary、SpaceBetween。点数≤5时只取首/中/末去重；>5取5个 floor(i*(n−1)/4)；无其他轴。

统计算法（A/java/com/hualala/linyu/data/SpendingAnalytics.kt:27）：过去7天含今天共7个日点，本月从1号到今天；缺消费日补0；无效日期、非数值/非finite/负金额跳过，0金额仍算一次；total为每日金额sum，count为有效记录数，average=total/count，count0时0。使用账单原日期解析后的本地自然日，排除start前和today后。

日期解析器（BillDateParser.kt:9）：严格`uuuu-MM-dd HH:mm:ss` / `uuuu-MM-dd'T'HH:mm:ss` / `uuuu-MM-dd HH:mm:ss.SSS`，系统时区，失败返回0毫秒。不接受任意ISO时区后缀。余额估算的旧billTimeMs是replace空格后LocalDateTime.parse，算法与趋势解析器**并非同一入口**。

iOS差距：I/OriginalRootView.swift:288–333 已填每日0、支持持久范围和读取trendType，但永远展开，没有trendCollapsed、3指标/count/average、日期选择、日详情、卡内图型切换、指定点和自定义轴。默认图表含平台轴，折线catmullRom，柱渐变，布局是范围另起一行，只有合计。`CampusBill.amount`无效金额变0且当前聚合无finite/负数过滤，未来当天时刻用`date<=Date()`而Android按整日。实现映射应为专用OriginalSpendingTrendCard + Canvas/Path，或彻底定制Charts做到同样坐标/点/命中，不能保留默认样式后称高保真。

## 4. 使用页 / ShowerScreen

来源：[ShowerScreen.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/ui/ShowerScreen.kt:31)。原版不是“大号计时器”页。

| 顺序 | 原版精确要求 |
|---|---|
| 背景 | 无自定义shower背景时Light垂直渐变`E3F2FD→BBDEFB→90CAF9`，Dark`1A237E→283593→3949AB`；有自定义背景时本页透明，不画自身渐变 |
| 主容器 | fullSize、verticalScroll、padding24，水平居中、垂直Arrangement.Center；不能把主按钮强制钉到屏幕底部 |
| 顶图 | 仅无customBg显示DeviceGlyph，emoji72sp或icon72dp，下8；🚿/🪥映射原始vector并白色tint，饮水机保持♨️/❄️emoji。有customBg连8间隔也删除 |
| 状态 | `statusText`22 Bold Accent；下4；location用M3 bodyLarge（默认16sp，字距/行高需保留平台度量核对）secondary；下32 |
| 预扣卡 | 全宽Surface、圆角16、Card、白描边1（Light .6、Dark .18）、零阴影；内20居中；「💧 已预扣 ¥$remaining」18 Bold Accent；下4；「计费以热水器显示为准」12 secondary；下24 |
| 已用时长 | 胶囊非全宽，圆角12，Card.copy(alpha=.6)（覆盖原alpha），Surface透明；内horizontal20/vertical10；⏱18，下一个文字前8；「已用 X分Y秒」或不足1分钟「已用 Y秒」，16 Medium primary |
| 自动倒计时 | 仅autoDisConSec>0显示；已用框下12；圆角12、Warning alpha.12，内20/10；⏳18+间8；「闲置约 X分Y秒 后自动关闭」或「闲置约 Y秒 后自动关闭」，13 Warning；不是独立大计时器 |
| 结束按钮 | 倒计时（若无则已用框）下48；全宽56高、CircleShape，固定`E53935`，禁用同色alpha.4，elevation4；正常「结 束 使 用」白18 Bold、letterSpacing4sp；Stopping时20 spinner/stroke2+间8+「正在关闭...」同字样式；disabled防连点 |
| 脚注 | 按钮下16；「费率: 0.041元/升 · 设备: ${location.takeLast(6)}」11 secondary、center；原版硬编码费率，不能无声改成动态文案 |
| 返回 | Column后上层的左上IconButton；statusBarsPadding+padding8，AutoMirrored ArrowBack primary；无障碍「返回（不结束用水）」；系统返回也触发minimize，不触发stop |

设备状态来源：DeviceInfo.statusText根据权威饮水机大类/独有名称判据选「正在接热水」「正在接凉水」；以洗手台开头「正在洗漱中」；其他「正在沐浴中」。location取formatDeviceName后的displayName。使用页外传selectedDevice?.typeEmoji/statusText/locationOnly，缺设备时默认🚿/正在沐浴中/空位置。（A/java/com/hualala/linyu/model/DeviceModels.kt:91–147；MainScreen.kt:173）

预扣卡label虽写“已预扣”，实际remaining初始为withholdMoney，MQTT消费更新后为max(preDeduct−consumeMoney,0)，是余额样数字。必须按现有语义如实复刻，不能把showerConsumed直接显示到这里。timer每秒由持久开始时间重新计算，自动倒计时由截止时间计算，恢复不重置截止时间。（MainViewModel.kt:900、942、955）

iOS当前`OriginalShowerView`（I/OriginalRootView.swift:245–274）：顶部“收起/淋浴”栏、恒定drop图、恒定「正在用水」、64 light rounded大计时器、名字、倒计时秒数、底部Accent按钮；缺预扣卡/中文已用框/费率脚注/状态词分支/红色按钮/精确间距/背景条件。现有`CloudActiveOrder`也没有preDeduct、consumed、device type字段，UI无法仅换皮显示原版remaining；需在建立订单时保存设备显示元数据/预扣并把MQTT消费映射进呈现状态（I/LinYuIOS/Transactions/CloudShowerController.swift:5）。`CampusDevice`已有withholdMoney、emoji、statusText可复用（I/OriginalAppModels.swift:104–134）。

返回映射：只清showShower/showCloudShower呈现绑定，保留交易/云订单/startedAt并显示原版toast「已返回主页，设备仍在运行」。原版minimize取消UI计时/轮询/MQTT但服务监控保留；当前iOSdismiss不显示该toast。停止映射继续调用model.endBluetooth/endCloud；关阀失败或未确认必须留在当前页并恢复可点，不得仅因请求结束退出。当前model.endCloud成功才清showCloudShower、BLE阀closed才清showShower已有基础。（A/MainViewModel.kt:1064、1078；I/OriginalAppModel.swift:288、298）

## 5. 与用水相连的弹窗、业务触发和接口

| 触发 | Android事实 | iOS当前入口/需补齐 |
|---|---|---|
| 开启中 | MainScreen.kt:422 非dismissible AlertDialog；标题「正在开启热水器...」Bold center；24 spinner/stroke2.5+间12；bleProgress或「正在确认设备是否开启，请稍候」；无按钮 | 当前页面末尾通用ProgressView，需对应业务阶段、不能仅global busy |
| 云端306 | MainScreen.kt:451 标题「要用蓝牙方式开启吗？」Bold center，正文设备名+三段说明，lineHeight20；全宽「用蓝牙开启」/「取消」；用户确认后才重试 | 当前confirmationDialog「该设备离线或需要手机蓝牙直连」大幅省略，需还原说明；不以smallTypeId=1自动判蓝牙 |
| 开阀失败 | MainScreen.kt:333 标题「开阀失败」或「开阀失败 · 有未扣账单」；err14 primary；仅SERVER_REJECTED可列未扣账单；下12「检测到 N 笔没扣成功的账单：」13 Medium Warning；下6逐行`· ¥money   date前16`12 secondary；下8说明「账户有欠费时服务端会拒绝开阀」11；有账单Warning「立即补扣」，无则「知道了」；另「关闭」 | 当前sheet/List非AlertDialog；保留明确服务端拒绝的资格判断；批量金额未知按共用确认禁用 |
| 批量二次确认 | 用同一个DeductConfirmDialog；detail「共 N 笔」；确认清错误，再串行deductAllUnpaid；不是自动重开阀 | 当前OriginalStartFailureView有二次alert但文案与未知金额策略不同 |
| 自动关停 | MainScreen.kt:484 非dismissible；标题「⚠️ 热水器已自动关闭」Bold center；设备行🚿16+设备名Medium；下6「⏱ 已用 X分Y秒」；下12：加载时14 spinner+间6「结算中...」，否则「本次消费：¥金额」Bold Accent，未知「消费金额稍后可在账单中查看」；全宽「确 认」调用confirmAutoClose | 当前alert仅设备/时长/稍后看账单，缺金额/结算状态、标题emoji、样式；当前业务检测自动结束后即清showCloudShower |

批量结果文案（MainScreen.kt:406）：未发出「没有可补扣的账单，或正在处理另一笔代扣」；纯未知「补扣结果未知，请下拉刷新确认后再操作」；混合未知「成功 N 笔、失败 N 笔、N 笔结果未知」；全成功「补扣成功，再试一次开阀」；全失败用首失败原文或「补扣失败，请到「钱包」页重试」；其余「成功 N 笔、失败 N 笔」。iOS现实现措辞不同。

业务接口映射（读取接口不等于授权在本次盘点实发交易；本次没有实发）：

| UI/状态 | Android业务入口 | 已有iOS等价入口及HTTP |
|---|---|---|
| 钱包进入、下拉 | loadBills / pullRefresh | OriginalAppModel.refresh():121，取当月和前两月；`GET /order/query/account/bill/list?month=yyyy-MM&billRequestType=2`；原版列表取20，趋势全history |
| 真实余额 | refreshWallet + loadCampusBalance | OriginalFeatureAPI.campusWallet:33；`GET /account/wallet`读money（不是accountRealMoney厘）；`GET /settlement/campus/userInfo`读amount；优先campus |
| 未扣/代扣 | loadUnpaidBills / requestDeduct(date) / deductAllUnpaid | `POST /order/weixinScorePay/unPay/queryBill`；`POST /order/thirdTrade/single/json/pay`，JSON `deductType=7, consumeDate, projectId, accountId, loginCode, userId, phoneSystem=WeChat`；日期是定位字段。OriginalFeatureAPI:71、86；OriginalAppModel:342、369 |
| 详情 | 原版UI只读选中DTO | iOS.loadDetail:336调用`/order/query/account/bill/detail`属于额外行为；呈现还原不应依赖网络成功 |
| 手填 | manualBalance+manualBalanceTime | model.setManualBalance:306，纯本地；需支持草稿校验/当前估算预填 |
| 使用页开始/恢复 | startShower / startLastDevice / enterShowerState | model.start:258 → cloud.open或transactions.open；现有账户隔离/防重继续保留；不得仅为改UI删除 |
| 使用页结束 | stopShower → ShowerController.closeValve 或BLE分支 | endCloud/endBluetooth；云端queryUsing→downRate→downRateResult开启；closeOrder结束并核对状态；iOS CloudShowerController保持同一业务入口 |
| 桌面选用 | ShowerController.pickDevice(mac)，只选设备不开阀 | iOS handle当前只有start/stop/show，缺pick；扩快照和事件路由方能等价 |

Android loadBills进入时先读账户cache，网络顺序取三个月，只有全部成功才持久化新缓存；isLoadingBills最后false。iOS已按月失败保留该月旧数据、去重排序、ownerScope隔离，属于业务保护，应明确与原版数据顺序有差别而不要删掉。显示状态至少需要`billsLoaded/isLoadingBills`、每笔deductingDate、趋势daily count、用水preDeduct/consumed/status metadata。现在iOS private deducing Set仅暴露全局isBusy，无法画出原版“当前一条扣款中…”。

## 6. Android桌面组件：全部布局和状态

源码：[WidgetRenderer.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/widget/WidgetRenderer.kt:22)、[WidgetActions.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/widget/WidgetActions.kt:25)、[LinYuWidgetProvider.kt](D:/User/Documents/move_to_ios/work/android-upstream/app/src/main/java/com/hualala/linyu/widget/LinYuWidgetProvider.kt:44)。实际渲染代码固定玻璃样式，不跟随App深浅；类头注释里“跟随壁纸明暗”等旧说明不能压过build实际实现。

### 6.1 材质资源

全部 `A/res/drawable/widget_*.xml` 已读。外玻璃22圆角：底`#6B0F1720`；对角315°白渐变`#21FFFFFF→#0BFFFFFF`；顶部270°白高光`#33FFFFFF`@0→`#0DFFFFFF`@.45→透明@1；白描边1/#2EFFFFFF。内槽15角、`#1AFFFFFF`、白边1/#29FFFFFF。按钮12角：start/选用`#14FFFFFF`、stop`#38EF4444`，均白边1/#29FFFFFF。头像圆、`#1AFFFFFF`、白边1/#29FFFFFF。nav active12角、`#24FFFFFF`、白边1/#29FFFFFF。三徽章20角、白边1/#29FFFFFF：idle底`#2E22C55E`，using`#383B82F6`，occupied`#2EF59E0B`。

tile18角；idle与外玻璃同色和渐变；using底`#CC2563EB`，occupied底`#CCB45309`，后二者叠315°`#33FFFFFF→#0DFFFFFF`、白边1/#3DFFFFFF。相关图标原vector24×24：蓝牙/卡片/箭头/时钟线宽2.2、电源/停止2.4、round cap/join；锁为白填色path。应复用vector path转换为iOS Path/单色asset，不能任意换成近似SF Symbols。

### 6.2 1×1

`A/res/layout/widget_linyu_1x1.xml:16`：root全宽高内6；叠idle/using/occupied/busy，仅可见块有点击。前三块居中竖排8sp状态字（单行/includeFontPadding=false），下1间20图标。idle字白.90，其他白；busy中央24白不确定进度。**实际有状态小字**，虽然源注释早期写“没有任何文字”。无设备名、金额、计时。

状态：「空闲」电源→开；「使用中」停止→关；「占用中」锁→仍可尝试开，由服务器判断占用是否结束；「未登录」「没设备」电源→开App。失败notice使用短文案；过程busy不接受点击。整个root边缘也挂同一动作，避免内边距死区。xml provider最小40×40、target1×1、禁止resize、不周期刷新、只home_screen，使用专门previewImage。

### 6.3 2×2

`A/res/layout/widget_linyu_2x2.xml:13`：root玻璃内12，竖向。首行状态点9sp；设备名左4、weight1、Bold13，可均匀缩9–13步1、start省略；只显示完整设备名最后一段。右徽章左4，文字10 Bold，内h8/v2：「● 空闲」`#F24ADE80`、「● 使用中」`#60A5FA`、「● 占用中」`#F2FBBF24`。副标题top1、start12、9sp、secondary`#ADFFFFFF`、末尾省略。

中槽marginTop5、高度weight1，idle居中「上次消费」10.5 secondary、下1「¥ —」或设备最近消费22 Bold白等宽数字；running居中Chronometer24 Bold白tnum、下1「预扣 · ¥金额」10.5 Bold secondary。busy中间20白spinner+间8文字12 Bold白。底部top6、高34、全宽start/stop玻璃按钮，中央24白vector；只有图标，无文字。

provider默认110×110/target2×2、horizontal|vertical resize。当前代码拉宽也保持同一套竖布局，不按宽高比跳横版；XML provider头注释的“两套布局”已过时。

### 6.4 2×4（实际宽4格×高2格）

`A/res/layout/widget_linyu_2x4.xml:14`：root玻璃；左48宽导航列，上下6，3个等分行；各38×38图标区、padding10，active玻璃底，white；inactive`#D1FFFFFF`。1宽分隔线`#29FFFFFF`；右视口weight1、内10，三页叠放。

- 控制页（:127）：头部与2×2相同，设备显示完整名；occupied字9.5。副标题同9sp。主体top5横排：左内槽weight1、右按钮宽86/满高/left10；idle「上次消费」10、金额21 Bold；running计时23 Bold、预扣10 Bold；busy20 spinner+间8、12 Bold；按钮图标24。
- 附近页（:365）：标题11 Bold secondary，后3同步时间9/#7AFFFFFF：「（刚刚）」「（N 分钟前）」「（N 小时前）」；未扫过不写括号。右强中弱图例9，green22C55E/orangeF59E0B/redEF4444，间5。最多2行，先按寝室rawName过滤再take2；各weight1、top3、内h7内槽；26圆头像+13emoji；left7内容，设备11 Bold白/start省略，类型9 secondary；类型后5信号点11，再3为9sp `-NN dBm`；末「选用」11 Bold白、left6、内h13/v5、start按钮材质。没有第二条就留空并禁用对应动作。
- 附近空态：11sp secondary居中；优先「请在 App 中开启扫描权限」→「请打开蓝牙」；曾扫无结果「未发现热水器」，未扫描「未扫描到附近设备」。不伪装实时扫描。
- 账单页（:637）：顶内槽h10/v5；label9.5 secondary；下一行15卡图标、left6余额18 Bold白tnum、右13chevron；下4「最近消费」10.5 Bold白；两行weight1：26头像/13emoji；内容left8，设备11.5 Bold白/start省略，时间9 secondary；右金额12.5 Bold白tnum。无cache第一行「在 App 里刷新账单」、后行「—」。整页点击开App钱包。
- **原版既存文案不一致**：WidgetRenderer.bindBills:625即便使用wallet真实余额，标签仍「一卡通余额」，无真实余额「一卡通余额（估算）」。这是原代码事实，不应把BalanceEstimator.title()理想映射写成已实现。
- provider默认250×110/target4×2，可双向resize、无周期刷新；nearby/账单是App上次快照，不实时拉取。

### 6.5 全部渲染和操作状态

`readState`（WidgetRenderer.kt:85）：LoggedOut优先；无lastSN→NoDevice；Running不受寝室过滤影响，必须保留停止入口；idle若不属于绑定寝室→NoDevice，否则Idle包含occupied标记。占用状态只来自查询明确isOwner=false，标记过期清理，不能由在线状态推断。

| 状态 | 2×2/2×4 文案/行为 |
|---|---|
| LoggedOut | 「未登录」「点此打开淋浴」，面板—；root开首页 |
| NoDevice | 「请先选择设备」，2×4副标题「点按钮选附近设备」且按钮切附近tab；2×2「点此打开淋浴」且按钮开首页 |
| Idle | 设备名/设备类型，绿点空闲；设备专属上次消费（>0才显示金额，否则¥ —）；面板点开钱包；电源开 |
| Running | 蓝点/使用中；计时+预扣；面板点击也可直接停；stop图标停止 |
| 过程 | 「正在开启…」「正在关闭…」「正在刷新…」「正在切换设备…」；全局busy，所有桌面实例同时显示；按钮禁用 |
| Unknown | 「点此刷新」；按钮只reconcile，不能重新发开阀 |
| Notice | 「网络异常」「设备不存在」「他人使用中」「开阀失败」；约3秒后清提示，允许再点；完整开阀失败原因由通知显示；1×1 notice不转圈 |

细节：2×2/2×4 bindPanels 对所有非空busyText都采用有spinner的busy面板，包含notice；1×1才用isNotice区分不转圈。不能因为枚举注释写“结果不转圈”就把大组件行为也记错。root总开首页；busy面板点击开钱包。2×4 tabs是组件内0控制/1附近/2账单，与App0首页/1钱包不同；选中tab按widget ID持久化。（WidgetRenderer.kt:394、478、727；WidgetActions.kt:25、51、121）

选用：Provider把本实例tab立即切控制页，显示SWITCHING，调用pickDevice(mac)，成功只更新当前设备，不自动开；失败保持原设备。开：queryUsing看是否已有本人订单，若他人订单不冒领；云开downRate后700ms确认最多9次/默认预算6秒；结果Unknown只允许重新查状态。BLE开交WidgetBleService；停也交服务以完成关阀+结算；服务失败恢复订单/开始时间，不能把未确认当结束。ShowerWatchService每15秒查，剩1–14秒时等到截止点再查，只有明确服务端订单不存在才自动结束；BLE不按云订单空值误判已停。（A/java/com/hualala/linyu/data/ShowerController.kt:191、294、365、432；service/WidgetBleService.kt:116、177；service/ShowerWatchService.kt:126、216）

## 7. 官方3.1.0与未发布3.1.1的Widget差别

已运行git diff，不是凭版本号猜测：

1. HEAD WidgetRenderer.kt:237传入`chronometerRunning = startedAtMs > 0L`，bindPanels:404新增此参数并:453传给setChronometer。v3.1.0始终running=true，缺开始时间可能从00:00走。图形布局完全相同；若目标严格官方APK须将此差别在验收表标为行为修复，而非原版已有。
2. HEAD LinYuWidgetProvider.kt:227 BLE开启改为`markDelegated()`，busy由WidgetBleService finally清；v3.1.0重复markBusy/render但没有delegated，广播返回会较早清掉“正在开启…”反馈。布局/正常文案不变。
3. 本次对上述UI/布局资源和余额/趋势/背景等文件的diff没有其他变更。ShowerController / service其它业务文件应由业务审计另行完整版本比较，本文不声称这两点穷尽整个仓库的v3.1.0→HEAD差异。

## 8. iOS WidgetKit现状、平台边界与等效路径

现状证据：[LinYuWidgets.swift](D:/User/Documents/move_to_ios/work/livecontainer-cloud/LinYuWidgets/LinYuWidgets.swift:5)、[LinYuWidgetSnapshot.swift](D:/User/Documents/move_to_ios/work/livecontainer-cloud/Shared/LinYuWidgetSnapshot.swift:14)、I/LinYuIOS/Models/OriginalAppModel.swift:412、478。

现有仅一个StaticConfiguration，small/medium/large；black.gradient底，淋浴标题cyan，余额/设备/大计时器，蓝色文字胶囊开始/结束，大号附3账单。15分钟after timeline，显示本地快照。整体widgetURL在有订单时**整块点击发stop**，否则start；与Android“root开首页、明确控件启停”不同。Link也都是打开App后handle URL，没AppIntent。没有1×1语义瓷砖、2×4侧栏/三页、附近快照、状态徽章、占用/未知/busy、预扣、设备专属上次消费、账单时间/emoji。

快照只有ownerScope/updatedAt/balance/balanceTitle/lastDevice/lastDeviceID/orders(id,title,startedAt,isBluetooth)/bills(id,title,amount)/controlNonce；保留了账户和nonce校验。publishSnapshot按内容变化才reloadAllTimelines，登出清空。新增等效显示需扩快照：last设备emoji/typeLabel/rawName/预扣/lastConsume；running preDeduct/remaining/startedAt有效性；nearby原始名/显示名/类型/emoji/RSSI/MAC/scanTime/权限阻断快照；bill time/emoji/raw值；busy/unknown/occupied；组件页配置键。迁移可选字段以兼容旧快照，不能把旧decode失败当新用户。

**当前LiveContainer发行配置本身不构建桌面widget**：`I/project-livecontainer.yml:13`定义LINYU_LIVECONTAINER、空AppGroup、仅app/test targets；Shared:26在此模式用standard而非共享group，OriginalAppModel:412禁用WidgetCenter。`I/scripts/package_ipa.py:48`明确拒绝.appex。普通`I/project.yml:30、51`才有嵌入LinYuWidgets target和AppGroup。这是当前工程可交付边界，不能宣称LiveContainer IPA已附可安装系统桌面组件。

等效路径（实现建议，未执行）：

| Android能力 | WidgetKit处理 |
|---|---|
| 2×2、2×4玻璃外观 | 在systemSmall/systemMedium按实际family尺寸复刻内部布局；不能把Android格子dp当iOS family尺寸。圆角受系统容器裁切，iOS17+显式containerBackground；内部材质/矢量/文字/颜色遵原版 |
| 1×1省空间 | iPhone主屏现有small family并非Android40dp tile；普通widget内可复刻tile样式但占系统small空间。锁屏accessoryCircular/Rectangular可作额外等效入口，不能称主屏1×1完全相同 |
| 不开App直接tab/选用/启停 | iOS17+ Button(intent:) / AppIntent；tab持久状态+重载，选择设备只更新共享状态，动作复用原业务控制。iOS16保留Link开App回退并明确记录功能差异 |
| 连续走秒 | 使用系统动态日期Text(.timer)/计时区间，无需每秒reload；无有效startedAt显示固定00:00，不能用Date()伪造开始时间 |
| busy和错误 | AppIntent完成前后持久状态；将重要视图invalidatableContent，操作结果写回共享快照。系统控制渲染和刷新时机，不能承诺任意每帧自定义动画或恰好3秒恢复；App端立即反馈沿用现有业务 |
| 自动刷新 | timeline与WidgetCenter只是请求，不是15秒后台常驻服务。保留快照同步时间，回App/用户操作重新对齐，不能以显示倒计时归零作为关阀证据 |
| BLE长连接/云订单监控 | 不能把Android前台Service原封搬到widget视图进程。需主App复用现有控制器、必要时AppIntent交前台完成；独立签名AppGroup/扩展方案需真机验证。本文不假定widget拥有无限BLE会话/后台执行 |
| LiveContainer | 此配置只能交付App内等效控件；要系统桌面widget需另做普通签名带extension的发行配置，不能靠把appex塞进当前IPA绕过项目约束 |

Apple文档只读核验（经agent-reach通用网页/Jina，2026-11-05）：交互按钮/Toggle通过AppIntent，widget渲染归档、不同进程，不能靠普通binding实时驱动；示例iOS17可用；动作完成后系统重载时间线。[Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)。刷新由系统预算和时间线控制，widget不会持续运行，动态日期可以在扩展未运行时继续显示计时。[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)。上表是基于这些边界及本项目代码的迁移推论，未把方案写成已验证功能。

## 9. 组件→iOS工作项与验收状态矩阵

| 原版组件 | 保留业务、替换呈现的iOS位置 | 必须覆盖的状态 |
|---|---|---|
| WalletScreen余额 | OriginalWalletView余额区+精确token card | campus/wallet/manual三来源、无数值、账单未加载、真实余额先到、手填草稿/取消/保存 |
| BillCard/详情 | OriginalBillRow+五行自绘对话框 | 三设备类型、日期截断、原金额字符串、未扣有/无、当前扣款中、未知金额确认禁用 |
| SpendingTrendCard | 新独立卡，模型复用bills history | 默认折叠/展开、跨会话、7天/本月、line/bar、点选、0消费、加载、月1号单点、31日轴标签 |
| ShowerScreen | OriginalShowerView结构整体替换 | 深浅默认渐变、custom有/无图标、四种状态词、预扣/消费更新、计时跨分钟、倒计时0隐藏、stopping/失败可重试、返回不断水 |
| 关联AlertDialog | RootView中startFailure/automaticFinish/fallback/loading | 明确拒绝与未知/网络错误区别、批量已知/未知金额、结算加载/金额/未知、外点能否dismiss |
| Android widgets | LinYuWidgets+Shared+model.publishSnapshot | 未登录/无设备/空闲/本人使用/他人占用/进行中/Unknown/Notice、近设备0/1/2、权限/蓝牙/未扫描、账单0/1/2、每实例tab/全局busy |

目前仅源码盘点完成，未做UI修改、未运行编译或真机视觉验收。本报告没有以“模型/接口已存在”替代UI等效完成；完成复刻必须对每个状态用同一内容、同一容器可用宽高逐张截图比对。

## 10. 阅读清单（完整与局部明确分开）

完整读过的Android文件（`A/java/com/hualala/linyu/`下，除资源）：

- ui/WalletScreen.kt、SpendingTrendCard.kt、TrendDisplayPolicy.kt、ShowerScreen.kt、DeductConfirmDialog.kt、DeviceGlyph.kt、AppBackgroundLayer.kt、theme/Theme.kt。
- data/SpendingAnalytics.kt、BillDateParser.kt、BalanceEstimator.kt、ShowerController.kt。
- model/DeviceModels.kt、WidgetCache.kt。
- utils/BackgroundManager.kt、BackgroundState.kt、MoneyFormat.kt。
- widget/WidgetRenderer.kt、WidgetActions.kt、LinYuWidgetProvider.kt（包含WidgetBridge）。
- service/WidgetBleService.kt、ShowerWatchService.kt。
- `A/res/layout/`全部3个文件：widget_linyu_1x1.xml、widget_linyu_2x2.xml、widget_linyu_2x4.xml。
- `A/res/xml/widget_info_1x1.xml`、widget_info_2x2.xml、widget_info_2x4.xml；`A/res/values/strings.xml`。
- `A/res/drawable/`：widget_avatar、widget_badge_idle/occupied/using、widget_btn_pill/stop、widget_glass、widget_inset、widget_nav_active、widget_tile_1x1_idle/occupied/using；ic_device_shower/sink；全部ic_widget_bluetooth/card/chevron/clock/faucet/lock/power/shower/stop（以上均.xml）。

完整读过的iOS文件（`I/`下）：

- LinYuIOS/Views/OriginalRootView.swift（包括首页、Wallet、Shower、GlassCard、Background、StartFailure、DeviceDetail）。
- LinYuIOS/Models/OriginalAppModels.swift、OriginalAppModel.swift、OriginalPreferences.swift、OriginalBackgroundPalette.swift。
- LinYuWidgets/LinYuWidgets.swift；Shared/LinYuWidgetSnapshot.swift。
- project.yml、project-livecontainer.yml、scripts/package_ipa.py。

局部阅读/定向核查（不冒充全文件已读）：A/java/com/hualala/linyu/ui/MainScreen.kt:1–540（包括所有与用水关联弹窗）；MainViewModel.kt:880–1030、1046–1186、1381–1410、1821–2240及属性/Prefs定向rg；model/LoginModels.kt:81–196（账单/未扣/详情模型）；utils/PrefsHelper.kt趋势默认项407–423；I/LinYuIOS/Network/OriginalFeatureAPI.swift:31–105（余额/账单/代扣）；I/LinYuIOS/Transactions/CloudShowerController.swift:1–56及预扣/倒计时/消费定向检索。PNG预览资产已定位但本次未进行视觉审阅，不声称已读像素内容。
