# Android 原版「我的 / 设置」UI 盘点与 iOS 映射

盘点日期：2026-11-05。只读源码核对；未修改产品或测试代码，未提交，未调用真实账户、通知、设备或网络写接口。

## 1. 版本与证据规则

- Android 工作树：`D:/User/Documents/move_to_ios/work/android-upstream`，HEAD `ff5f8befb2416a21955927c54677e26740a4002a`。
- 官方 `v3.1.0` annotated tag对象：`761ae9b51bb0168b5a4de63a91f5168328107234`，实际源码commit（`v3.1.0^{commit}`）：`a650066a9624681a0e3404063219435d3717fa98`。用户已确认以官方v3.1.0为目标。已执行 `git diff v3.1.0 HEAD --` 本文全部指定 UI / theme / background / PrefsHelper / ApkUpdater / Notifier 文件，**空 diff**。因此本文这些布局同时适用于 v3.1.0 和当前 HEAD。`app/build.gradle.kts:29` 仍是 `versionName = "3.1.0"`；不能用“3.1.1”标记这批 UI 来源。
- `MainViewModel.kt` 有未发布差异：扫描查询去重、设备详情错误反馈、BLE 重连停止与 widget busy 收尾；本页 loadUseCode / generate / claim / account / campus balance / applyBoundRoom 的实现未改。选择寝室数据来自附近设备，因此扫描依赖的性能/错误状态需与主任务版本目标保持一致。
- iOS 基线：`D:/User/Documents/move_to_ios/work/livecontainer-cloud/LinYuIOS`。
- 下文 `A/` = Android `app/src/main/java/com/hualala/linyu/`；`I/` = iOS `LinYuIOS/`。`文件:行` 为本次读到的行号。明确写出的 dp/sp 是源码值；Material3 默认字号、组件最小触控尺寸、默认内部 padding 未在业务源码显式重设，须以该项目 Compose BOM `2024.02.01`（`gradle/libs.versions.toml:12`）解析出的组件实现为准，不能把 SwiftUI 系统默认值当作等价参数。

## 2. 全局视觉 Token（所有卡片、弹窗、背景共用）

来源：`A/ui/theme/Theme.kt:16–45,85–109`。

| Token | Light ARGB | Dark ARGB |
|---|---|---|
| Background | #FFF1F5F9 | #FF0E131D |
| Card | #B8FFFFFF（184/255 ≈72.16%） | #BF1D232E（191/255 ≈74.90%） |
| SolidSurface | #FFFFFFFF | #FF161B22 |
| Primary | #FF0D1117 | #FFE6EDF3 |
| Accent | #FF2563EB | #FF58A6FF |
| TextPrimary | #FF111827 | #FFE6EDF3 |
| TextSecondary | #FF6B7280 | #FF8B949E |
| Success | #FF22C55E | #FF3FB950 |
| Warning | #FFF59E0B | #FFD29922 |
| Danger | #FFEF4444 | #FFF85149 |
| ActiveBg | #FFFFF7ED | #FF1B1F23 |
| SurfaceVariant | #FFF0F0F0 | #FF21262D |
| Border | #14000000（20/255 ≈7.84%） | #14FFFFFF（20/255 ≈7.84%） |

- `BaseCard`：全宽；22dp 圆角；Card 纯色透明填充（没有 Material 模糊）；0.8dp Border；elevation=0。内部大多 padding=20dp。`A/ui/UserScreen.kt:443–454`。
- 主题色仅由 **home 背景**提取色覆盖 Accent；shower 的提取色不覆盖全局 Accent，也不改变深浅模式。Material primary=Accent；onPrimary Light=#FFFFFFFF、Dark=#FF062E6F。全局 ripple=Accent alpha 0.35；部分行显式关闭 ripple，见各组件。`Theme.kt:85–109`。
- iOS `OriginalGlassCard` 是24pt圆角、`.ultraThinMaterial`、白色 alpha0.28描边0.8（`I/Views/OriginalRootView.swift:159–166`），与原版的22dp、固定半透明实色、黑/白低透明描边不一致。默认背景为系统 grouped color 且总加载 OriginalHome/OriginalShower 图片（:169–180），原版未启用自定义时只有 Background 色。
- iOS `accentColor` 无图片时固定 `.blue`（`I/Models/OriginalPreferences.swift:28–30`），未区分原版 Light/Dark 两个精确蓝色。所有 `.primary/.secondary/.headline/.caption` 当前均不是原版显式 Token/字号的保证。

## 3. 页面结构与导航

### 3.1 我的主页面

`A/ui/UserScreen.kt:130–302`：进入时 loadUseCode、loadAccountInfo、loadCampusBalance；全屏 Column + statusBarsPadding + verticalScroll + 四周20dp。标题行 SpaceBetween、居中对齐；左「我的账号」22sp Bold TextPrimary。右依次：编辑 TextButton（横 padding8dp，文字14sp Accent，编辑态「完成」）、主题 IconButton（当前 DARK 显示🌙，否则☀️，20sp，点击位置是圆形揭示原点）、设置 IconButton（Material Filled Settings，TextSecondary，无文案，仅 contentDescription「打开设置」）。下空16dp；若明文降级警告再空16dp；卡片间16dp；末尾额外100dp为浮动导航留白。

默认 profile 卡顺序 ACCOUNT / USE_CODE / BOUND_ROOM；默认 settings 顺序 NOTIFY / TREND / BACKGROUND / LOG / ABOUT / UPDATE（`A/ui/UserCardLayoutPolicy.kt:9–22`）。隐藏项正常不显示，编辑模式显示所有卡；卡片可跨页移动；设置显示时通过回调通知父级，销毁时复位 false。背景页面和日志弹窗都可从任意迁移后的卡片打开。

iOS `OriginalProfileView`（`I/Views/OriginalProfileView.swift:11–37`）：标题「我的」largeTitle；卡间18pt；主题是SF Symbol +无指定参数 withAnimation；所有子页用 sheet；底部额外「编辑卡片」和「退出登录」；下拉刷新；这些层级、文案、入口位置与原版不同。原版主页面没有退出按钮或独立卡片编辑页；没有这里的下拉刷新。默认三卡顺序在 preferences 中已相同，可复用数据。

### 3.2 设置页面

`UserScreen.kt:353–419`：在原 UserScreen 内替换为 SettingsScreen，非 sheet。BackHandler/左箭头都返回我的；全屏滚动 + statusBarsPadding +20dp；标题行：返回 IconButton（TextPrimary，description「返回我的页面」）、「设置」22sp Bold、弹性空白、编辑/完成 TextButton（Accent）。下16dp；同款可编辑卡与16dp间隔；退出登录 OutlinedButton 全宽圆角14dp Danger；下8dp；页脚「Hualala v{VERSION_NAME} · 哗啦啦啦啦让我去淋浴~」12sp TextSecondary；末尾24dp。

iOS Settings 为 Form + navigationTitle +完成，新增「外观」system/light/dark Picker、图表类型Picker、iOS平台说明，无原版页脚和设置页退出（`OriginalProfileView.swift:166–218`）。这些是复刻差异；平台真实能力差异需另外说明，不能把工程状态说明当作原版UI。

### 3.3 内联卡片编辑

`UserScreen.kt:456–511`：编辑态每卡上方操作条 bottom4dp；标题13sp TextSecondary，隐藏时「{title}（已隐藏）」且标题alpha0.6；右侧四个34dp IconButton：跨页箭头Accent（我的→右箭头/「移到设置页面」，设置→左箭头/「移到我的页面」）、上移、下移（不可移时TextSecondary alpha0.3）、眼睛显示/隐藏（隐藏时ic_visibility+Success，未隐藏时ic_visibility_off+TextSecondary）。被隐藏卡片本体alpha0.45，仍可看见和操作。上/下移动为相邻交换，无拖拽或排序动画；移到另一页追加到末尾，并同时清除两页该卡的隐藏状态。

持久化：枚举名逗号串；restorePages忽略未知值、去重、避免两页重复、补回未分配默认卡；若新两页order都空且有旧order则按默认归属迁移，并继承legacy hidden；`UserCardLayoutPolicy.kt:24–76`、`UserScreen.kt:151–187,256–292`、`PrefsHelper.kt:244–250`。

iOS CardEditor为独立List，使用Toggle+ellipsis Menu+系统拖动handle（:220–239）；迁移卡只更改order，不清除两边hidden，行为也不同。现有preferences四个Published数组/集合可复用，但交互需改为原位编辑。

## 4. 各卡片、弹窗与完整状态

### 4.1 账号信息 + 账号管理

`A/ui/UserScreen.kt:514–606,1225–1244`：没有头像、卡片大标题或默认「趣智校园用户」。padding20；每行 minHeight26dp，左右 SpaceBetween；label TextSecondary默认Material文字，值Medium TextPrimary默认文字；姓名非空才整行出现；手机号总有（原号，无掩码）；学校总有（来自model.schoolName，空则Prefs）；学号非空放学校下面；行间10dp。最后12dp + Border Divider；居中「账号管理」13sp Accent，右4dp空白+18dp上下箭头；header圆角10dp、vertical padding8dp、整行可点。默认收起；展开后两TextButton SpaceEvenly：「更换手机号」「修改密码」13sp Accent；无展开动画声明。

iOS头像46、姓名占主标题、学号/掩码手机号占副标题、缺手机号行、账号管理sheet（:45–53）。现有 `model.account?.profile`/`auth.session.telephone`可直接映射原版行；iOS账户profile中name/studentNumber/schoolName已经是可选值。

**更换手机号 AlertDialog**（:1253–1356）：标题Bold「更换手机号」；外点/返回仅submitting=false可关闭。正文「当前手机号：{完整旧号}」12sp Secondary，12dp后新手机号OutlinedTextField单行、Phone键盘、圆角12、全宽、trim；10dp后验证码单行数字OutlinedTextField weight1、圆角12；横10dp后发送按钮宽86dp、圆角12、水平contentPadding4，文字13sp单行。按钮可用条件 !sending && countdown==0 &&新号length==11；发给**新号** typeId=5；成功60s，每1000ms减1；显示「60s」…「1s」，无倒计时则「发送」；sending维持整个倒计时。发送错误=r.exception.message或「验证码发送失败」，下10dp，Danger12sp。提交「确定」/「提交中…」，可用条件 !submitting &&新号11位&&code非空；「取消」提交时禁用。updatePhone success后写Prefs.telephone、restoreFromPrefs、model.phone；toast「手机号已更换」并关闭；服务错误displayMessage或「更换失败」，异常「网络异常，请重试」。注意:1246–1250遗留注释错误说发旧号，实际实现1297及1270解释明确发新号。

**修改密码 AlertDialog**（:1369–1522）：默认直接密码模式。当前密码、10dp、新密码、10dp、确认新密码；均单行Secure/Password keyboard、圆角12、全宽。短信模式把当前密码替换为可编辑预填手机号（trim、Phone）、10dp、验证码数字field与86dp发送按钮；typeId=2，同样60s、发送可用需phone11位。字段后10dp为模式切换Text「短信验证修改密码」/「直接修改密码」，Accent12sp，圆角4、padding vertical2 horizontal3；提交中不可切，切换清error。error前8dp Danger12sp。提交只检查两次密码一致，否则「两次输入的新密码不一致」；不额外限制密码规则。直接模式需oldPwd非空；短信模式需code非空；均需new与confirm非空且!submitting。旧/新密码MD5取后10位大写；直接updatePassword，短信forgetPassword；成功toast「密码已修改」并关闭；失败「修改失败」或服务器文案，异常「网络异常，请重试」。「确定」「提交中…」「取消」及外点锁定与换号一致。短信mode输入phone仅用于发验证码，forget请求认证仍NetworkModule.authFields（不是替换账号手机号）。

iOS `OriginalAccountManagement:124–164`把三个流程并列Form、无确认新密码、无60s、无11位UI gating、成功不关闭、消息文案不同、重置手机号不可编辑。可复用 `model.api.sendAccountSMS(...purpose:.newPhone/.forgotPassword...)`、updatePhone/updatePassword/forgetPassword，以及`auth.replaceSession`；保留其transactionInProgress锁，不要破坏真实账户事务保护。API已处理相同typeId与MD5后10位，无需UI重复加密。

### 4.2 使用码卡

`A/ui/UseCodeSection.kt:87–194`：padding20；第一行「使用码」Secondary13sp，右「后三位为手机号后三位」Secondary11sp；4dp后码28sp Black，字距6sp，前缀Primary/后三位Accent；无码且loaded「尚未领取」28sp Black Secondary/6sp；未loaded「加载中...」28sp Black Primary/6sp。4dp后行左「使用码已开启」/「使用码已关闭」Secondary12sp，右Switch：checkedThumb=Accent、checkedTrack=Accent alpha0.5；切换立即本地optimistic更新，异常回滚，网络类toast「网络连接失败，请检查网络设置」，其它「操作失败，请重试」。注意非exception服务业务failure未检查success，忠实记录源码行为。

行后「在热水器物理键盘上输入此码」Secondary12sp；12dp+Border Divider；CollapsibleHeader「领取使用码」（无码）/「重新领取」（有码），默认收起。展开时resetAvailability==0显示服务端warn Secondary11sp居中、6dp后按钮，按钮仍可点。按钮全宽圆角12、Accent，文字同header。

iOS `:54–66`使用headline、34pt Bold monospace、无6字距；后3位 `.foregroundColor(.blue)`作用在拼接后的整个Text，**整串蓝色**；开关顶置；无说明、loaded区分、折叠、状态文案。resetAvailability==0走toast不弹「无法领取」；卡片按钮固定「领取 / 重新领取」。`model.account.useCode`可用；缺专用useCodeLoaded标志，不能用nil同时表达加载与无领取。

**领取弹窗**（UseCodeSection:196–393）：AlertDialog非sheet；title Bold：blocked「无法领取」，无码「领取使用码」，有码「重新领取使用码」。blocked正文14sp Primary server warn或「1天只能领取一次使用码」，仅「知道了」，不生成候选。正常打开即swap（消耗一次generate额度，注释每日20次）；取消只关闭，不调用set，不替换当前码。

正常正文：如有码，上行左「当前使用码」12sp Secondary，右当前码12sp Secondary字距1；下14dp。候选行左Column：「领取后替换为」Secondary12sp、2dp、候选24sp Black字距3，后3位Accent/前缀Primary；未生成为「— — — — — — — —」Secondary；过期整串Secondary。右TextButton：Refresh18dp Accent+4dp+「换码中」/candidate空「获取」/其它「换一个」13sp Accent；!swapping&&!claiming可用。下6dp，candidate存在时「请在 m:ss 内领取」Secondary11sp，每1000ms减秒，从180秒开始；过期「已超时，请重新换一个」Danger11sp。remainTimes存在下2dp「今日还能换 {n} 次」Secondary11sp；error下8dp Danger12sp。generate无model「当前无法换码」，失败「换码失败，请重试」。确定可用candidate!=null&&!expired&&!claiming&&!swapping，文案「确定领取」/「领取中…」；成功toast「使用码已更新」关闭，失败「领取失败，请重试」。claim中禁外点/取消，其余状态允许取消；swap中可关闭。

iOS `OriginalCodeCandidateView:82–102`是medium/large sheet、38pt整串码、秒倒计时、无过期颜色/按钮disable、无当前码行/后3位高亮/blocked对话框、附加解释文本。`model.generateCode()`、claimCode()已实现180秒服务前gating、createdAt/remainTimes/candidateClaimed，直接复用；需要UI区分swapping/claiming并补对应文案与禁用策略（现candidateWorking将两者合一）；成功message与错误展示可局部映射，不要将全局message误留在其它页。

### 4.3 绑定寝室

`A/ui/UserScreen.kt:609–708`：padding20；「绑定寝室」16sp SemiBold Primary；8dp；有绑定行「🏠 {roomKey(boundRoom) ?? boundRoom}」Medium Primary默认字号、1行尾省略、weight(1,fill=false)，8dp后「取消绑定」TextButton Danger12sp（调用applyBoundRoom空串）；空态「未绑定寝室，设备列表将显示全部设备」Secondary12sp。12dp后「选择附近」OutlinedButton全宽圆角12。

选择AlertDialog title Bold「选择设备位置」；nearbyDevices原始deviceName（或name）→roomKey→按首次出现去重；无设备「附近暂无设备」Secondary；有设备LazyColumn全宽maxHeight210dp（非固定高）；每条全宽TextButton，正文TailEllipsisText14sp Primary全宽：先按0.92递降字号直到≥原字号78%，再78%字号保留最长尾部并加前导「…」，不换行；选即关闭、applyBoundRoom(key)、toast「已绑定寝室：{key}」。无confirm，仅dismiss「关闭」。无手工输入。

`DeviceModels.kt:171–250`：roomKey剥类型前后缀、末尾房、trim/小写、连续分隔归一为“-”，保留楼层/楼栋；兼容短旧绑定需equals或后缀“-key”，不使用contains。`MainViewModel.kt:1505–1559` applyBoundRoom还会清掉非活跃且寝室外上次设备并刷新widget。

iOS :67–68无🏠、行结构不同，picker :104–122是整页List，按**每台meter**列，不去重、带RSSI、额外扫描按钮，点击choose会先连接设备。可复用nearby+ble.meters与OriginalFormatting.roomKey/inSameRoom（`OriginalAppModels.swift:213–224`），bindRoom会规范key并持久化；但bindRoom当前仅写account+persist，缺Android上次设备/快照收尾，需在model层补齐，不能只换UI。

### 4.4 通知

`A/ui/UserSettingsCards.kt:94–214,251–279`：BaseCard padding20；第一行左title「通知」16sp SemiBold Primary+4dp，说明13sp Secondary：开「用水期间和结束时收到系统提醒」/关「已关闭全部通知」；右12dp+Switch checkedTrack Accent。所有五个偏好默认true（PrefsHelper:377–399）；总关只隐藏详细区与权限警告，保留子偏好。

!allowed && enabled时下12dp出现全宽Warning alpha0.12 Surface、圆角10、内12：标题「请打开通知权限」13sp Medium Warning；4dp；「开启后才能收到用水提醒和结束通知。」12sp Secondary；8dp；「去开启」Button圆角10 Accent、13sp。Android13+请求权限，老版跳系统通知页；仅进卡片重读权限与请求结果，不存在业务源码resume observer。

enabled时下10dp出现「详细设置」13sp Accent，整行SpaceBetween，上下8dp，无ripple；右20dpAccent上下箭头，描述收起/展开；默认折叠。展开四行，每行vertical6dp，title14sp Primary、desc11sp Secondary，右12dp+Switch Accent：

| title | desc | preference |
|---|---|---|
| 用水状态通知 | 使用期间在通知栏显示已用时间 | notifyInUse |
| 使用结束通知 | 停止后显示用时和消费金额 | notifyFinished |
| 自动关停提醒 | 设备超时自己关闭时提醒 | notifyAutoClose |
| 横幅提醒 | 开阀失败、设备被占用时从屏幕顶部弹出 | notifyAlert |

iOS两处实现(:69、178–183)均直接铺五开关，标题和解释缺失/改变，没有权限状态读取与条件Warning卡。现OriginalNotifications只有requestPermission Bool，没有authorization状态可观察接口或打开系统设置方法。可复用五preferences绑定，但UI权限检测和系统设置入口需新增。

系统通知依赖（`A/utils/Notifier.kt:31–446`）：in-use低优先静音持续通知，title「正在使用 · {shortName}」、系统chronometer、固定ID1001、按钮「结束使用」、点正文回使用页；多台「正在使用 {count} 台设备」「点按查看进行中的用水」；停止过渡「正在结束 · {deviceName}」「确认关阀并结算中…」；结算「用时 {duration} · 结算中…」；完成「使用结束 · {shortName}」/「设备已自动关停 · {shortName}」，body money==null「用时 … · 结算中」、>0「用时 … · 消费 ¥…」、0「用时 … · 无消费」，点完成回账单；设备占用「设备占用中」/「{shortName}正在被他人使用」；开阀失败「开阀失败 · {shortName}」+服务原因；未确认关阀「关阀状态未确认 · {shortName}」「网络异常，设备可能仍在用水，请重试」；明确拒绝「关阀失败 · {shortName}」+原因。shortName最长14字符，超长前导省略保留后13；formatDuration=0 秒 / n 秒 / n 分 n 秒 / n 小时 02 分。横幅开关应只控制HIGH vs DEFAULT，不禁止异常事件本身。

iOS `OriginalPlatformServices:24–57`通知始终前台banner+sound，active只有结束用水action，缺系统chronometer；`OriginalAppModel:426–442`异常事件被notifyAlert直接禁发，语义不同；标题/金额/时长/点击完成到钱包均未按原版映射。iOS系统通知渲染和后台保证无法像素复刻；保留文案、事件和目标语义，不能承诺不存在的Android常驻服务能力。

### 4.5 消费趋势

`UserSettingsCards.kt:223–248`：全宽padding20 Row；title16sp SemiBold Primary+4dp；description13sp Secondary，开「在钱包页显示消费统计图」/关「已隐藏钱包页的消费统计图」；右12dp+Switch Accent。只控制趋势卡显隐、不修改账单。设置卡没有图表类型Picker；iOS :70/:184额外「折线/柱状」需移回原钱包趋势区域（主任务处理）。preferences.trendEnabled可直接复用。

### 4.6 背景装扮入口卡

`UserScreen.kt:734–756`：BaseCard Row padding20 SpaceBetween/Center；左weight1「背景装扮」16sp SemiBold Primary；4dp；home或shower任一enabled→「已启用自定义背景」，否则「使用自己的图片打造专属界面」12sp Secondary；右「更换」Button圆角14、Accent。iOS :71/:77–79仅图标+标题+chevron整行快捷入口，缺描述与按钮。

### 4.7 运行日志入口卡

`UserScreen.kt:711–730`：同上；「运行日志」16sp SemiBold，4dp，「查看/导出运行日志，便于排查问题」Secondary12sp；「查看」Button圆角14 Accent。iOS为快捷入口（:73），缺原版结构。

### 4.8 关于项目卡（内容在卡内，不是二级页面）

`UserScreen.kt:1149–1223`：padding20；「关于项目」16sp SemiBold Primary；10dp；「一款趣智校园第三方客户端」Secondary13sp；6dp；「项目名：淋浴（Hualala）」成功取stars才追加「 · ⭐ {n}」；6dp；「制作者：{ownerLogin非空或yehu-imei}」；6dp；「联系方式：」+Accent可点击「2276391153@qq.com」（同13sp）；14dp后全宽Accent按钮圆角12「访问 GitHub 仓库」。加载repo一次进程缓存；失败省略stars，不造假；邮件ACTION_SENDTO mailto，仓库用API htmlUrl fallback项目地址，外部打开失败静默。

iOS :303–308是说明性List sheet，没有星数、作者、邮箱；新增“当前状态/待Xcode验证”工程文案不是原版。可用Link/openURL承接邮件/仓库；暂无repo metadata model/cache接口，需增加只读服务。

### 4.9 应用信息 / 软件更新卡

`UserScreen.kt:760–1145`：编辑条title仍「软件更新」，卡内title「应用信息」16sp SemiBold Primary；padding20；4dp「当前版本 v{BuildConfig.VERSION_NAME}」Secondary13sp；8dp后状态13sp Medium：checking/未checked「正在检测更新…」Secondary，releases空「检测失败（多为网络原因）」Warning，有新「发现新版本 {latestTag}」Accent，否则「当前已是最新版本」Success。首次自动拉releases，缓存整个进程，最多10，过滤prerelease；版本数字比较忽略v且补0，不能简单tag字符串不等就更新。

有release：14dp+Divider Border+10dp；「更新日志」14sp SemiBold；2dp；默认最近3条，初始都不展开，只允许一个expandedTag；每行vertical8dp，无ripple，tag13sp SemiBold Primary；当前tag完全相等时6dp后「当前」10sp Success，Success alpha0.12底、圆角4、padding h5/v1；右Secondary上下箭头；展开正文12sp Secondary，下padding6；仅保留Markdown标题含“新增/功能/修复/BUG”的段落，去**/__ /反引号，标题剥emoji/#，空fallback「本版本未填写更新详情。」；日期publishedAt前10字符11sp Secondary alpha0.7、bottom6；Divider Border。有>3条则全宽TextButton「展开全部」/「收起」Accent12sp。

14dp后全宽Accent Button圆角12，「检查更新」/「检查中...」，checking不可点；点击reset非下载中状态再检查。有更新再12dp+Divider+12dp进入**同卡内**下载区，不弹sheet。

下载四态（:883–1013）：Idle为源选择+10dp+「下载更新」全宽Accent圆角12，有url才可点；Failed为Warning alpha0.12/圆角10/内10错误12sp，8dp+源选择+10dp「重新下载」；Running顶部左「正在下载更新包…」Secondary13sp、右已下载/总大小Accent13sp Medium（无total只已下载），8dp后全宽6dp LinearProgress Accent/Border，percent<0不确定；4dp后全宽TextButton「取消下载」Secondary13sp；Done「更新包已下载完成」Success13sp Medium，8dp后全宽Success Button圆角12「立即安装」，6dp后「请在系统设置里允许「安装未知应用」」Secondary12sp。installError下8dp Warning Surface同失败样式。字节格式≤0空、<1024 B、<1MB整数KB、其余1位MB。

源选择（:1022–1043）：左「国内镜像下载」Primary13sp Medium+下一行11sp Secondary（开「Gitee 直连，通常几秒下完」/关「GitHub 源，国内可能要几分钟」）；右12dp+Accent Switch。默认镜像true；镜像拼不出回GitHub。取消回Idle、非失败；下载进程级scope、attempt token、防tab切换中止；校验size、可选SHA256、包名签名；错误涵盖网络/超时/HTTP/缺包/安装器/未知来源设置。`ApkUpdater.kt:31–428`。

iOS :280–302是独立List sheet，当前开发版工程文案、仅3条DisclosureGroup、完整原始Markdown、无自动更新状态比较/缓存/当前徽标/展开全部；下载和安装四态均缺。**平台适配点**：不能把Android APK的下载/安装映射成可用iOS更新行为；外观、版本列表与检查状态可精确复刻，实际安装动作需使用真实iOS分发渠道。现有OriginalRelease缺publishedAt/assets/name，需扩展只读metadata服务，并把view从sheet搬回原卡内。

## 5. 自定义背景全屏页

`A/ui/CustomBackgroundScreen.kt:52–310`：全屏Dialog(usePlatformDefaultWidth=false)，SolidSurface完全遮挡；BackHandler/外关闭/左箭头返回；Column statusBarsPadding +verticalScroll +20dp。头左返回Icon TextPrimary+「自定义背景」20sp Bold；下12dp；两个等宽ScopeChip间10dp（「主页」「使用页」），圆角12、0.8dp Border，选中Accent/白字，未选Card/Primary，vertical10dp、14sp Medium。下6dp说明Secondary12sp，home「应用于：首页 / 账单 / 我的」，shower「应用于：洗澡中的使用页」；下14dp。

预览全宽高200dp、圆角18、底Background、居中；有图：Crop填满，alpha=opacity、blur=blur.dp、RGB brightness乘法矩阵；叠加示例Surface宽70%并外padding16，圆角14、Card、0.8 Border，内14，「示例卡片」14sp SemiBold Primary+4dp+「文字在背景上的可读性效果」12sp Secondary；无图仅「未设置背景」Secondary默认文字。下16dp全宽Accent按钮圆角14「选择背景图片」/「更换背景图片」，调用系统photo picker仅图片；取消不变，保存失败仅log，不弹额外错误UI。

有图时下20dp显示主题色行：「主题色」Secondary13sp，10dp，20dp圆色块（已提取RGB或Accent），8dp，「已根据图片自动提取」/「使用默认强调色」Secondary12sp；下8dp，再三个SliderRow：vertical6dp、上行label Secondary13sp、右值Primary13sp、Slider thumb/activeTrack Accent。透明度0.2…1显示整数%，模糊度0…20显示整数，亮度0.4…1.5显示整数%；实时持久化，不需要保存按钮；**无启用开关、无主题切换控件**。

最后24dp+全宽OutlinedButton Danger/圆角14「恢复默认背景（仅当前页面）」+60dp底留白。点击先确认AlertDialog圆角20、SolidSurface，title Bold「恢复默认背景？」；text Secondary「这将移除当前页面的自定义背景及相关效果。\n不会影响深色 / 浅色模式。」；confirm Button「恢复默认」执行删除当前图、enabled=false、themeColor=null、version++、preview=null；cancel TextButton「取消」。源码clear并未reset效果数值，下一次选新图会reset。

状态与图片：上次scope持久化Prefs.backgroundScope；home/shower相互独立；新图保存后enabled=true，opacity1/blur0/brightness1，imageVersion++；theme提取在IO后保存。BackgroundManager读取私有background_{scope}.jpg，JPEG95，解码inSampleSize按2倍递增使两边≤2560（这不是精确缩至2560），按scope/mtime缓存；颜色提取48×48、RGB每通道32一档量化、排除S≤0.15/V≤0.20/V≥0.95，最多颜色夹S0.35…0.75/V0.45…0.85。AppBackgroundLayer只在enabled绘制Crop图，alpha+blur+RGB gain，图版本/scope改变再取图。`BackgroundManager.kt:24–140`、`BackgroundState.kt:8–76`、`AppBackgroundLayer.kt:27–55`。

iOS :241–262使用Form，标题「背景装扮」、系统segmented、180高无示例卡的preview，始终显示三slider（透明度0…1、blur0…30），无数字百分比/主题色/适用页说明；恢复直接执行无confirm。`OriginalPreferences.backgroundScope`目前只内存没有存UserDefaults；reset背景后仍加载bundled图片，与Android默认无图不同；resetTuning与原版clear效果数值行为不同。setBackground与OriginalBackgroundPalette已提供JPEG95、2560最大边、48×48量化/HSV范围、RGB乘法brightness及缓存，适合直接复用；iOS导入是精确thumbnail最大边2560、tie排序规则也不同于Android hashMap最大项，极端图像可能提取不同颜色，视觉验收时需记录。无需为还原UI重写已可用API。

## 6. 运行日志弹窗

`A/ui/LogViewerDialog.kt:38–191`：Dialog标准平台宽，固定屏幕高度85%；SolidSurface、圆角20；头padding start20/end8/top12/bottom12，左「运行日志 ({logs.size})」16sp Bold Primary，右Close IconButton Secondary/description关闭；Divider默认色。中部weight1；无日志居中「暂无日志」Secondary；有日志Column内h14/v8垂直滚动，每条10sp Monospace Primary、vertical1dp。右侧自绘可拖scrollbar：触控宽20dp、全高vertical8；thumb固定40dp高，20dp拖动区中右对齐4dp实际条、TextSecondary alpha0.45、圆角2，位置=可移动行程×scroll比例，拖delta比例scrollTo；没有只滚动时才显示的淡出动画。

底Divider +Row padding16、两等宽按钮间12：「清空」OutlinedButton圆角12立即AppLogger.clear及logs空；「导出/分享」Accent Button圆角12，文字白，调用exportLogs。打开时读内存snapshot（非自动订阅）；最多内存300条。导出优先文件最后500行，空再内存；无日志只warning后return；生成cache/linyu_log_{time}.txt，系统分享标题「分享日志」，text/plain。AppLogger文件最大2MB超后保留后半，日期MM-dd HH:mm:ss.SSS+[D/I/W/E]，手机号及password/loginCode/secret/telPhone/telephone/smsCode/useCode/userId/accountId/独立code脱敏。`AppLogger.kt:22–170`。

iOS :264–270是NavigationStack+List，字号系统caption、标题无条数、无空态/固定85%/自绘可拖条/底部双按钮；按钮在toolbar。OriginalLogs持久化保留300行，export直接返回linyu.log（未做500行临时副本）；日志格式也不同。可复用logs.entries/clear/export作为底层入口，补精确呈现与导出语义；不必改成Android日志原路径。

## 7. 主题切换动画精确参数

`A/ui/theme/CircularRevealTheme.kt:39–167`：只有LIGHT/DARK，默认Prefs LIGHT。按主题按钮中心取屏幕原点；若Offset.Zero回退x=screenWidth−36dp/y=48dp；动画中忽略重复点击。遮罩先入composition、Animatable.snapTo(0)、等待一帧，再tween 650ms、CubicBezier(0.4,0,0.2,1)，到1后提交主题与持久化。进度<0.2仍旧主题；≥0.2切内容新主题并同步状态栏preview。旧主题Background遮罩在圆外绘制：maskAlpha=clamp(progress/0.2)，radius=clamp((progress−0.2)/0.8)×max(距四角)×1.15。仅渲染一次内容，不重建页面/请求，不丢折叠和输入状态。

iOS现withAnimation无指定时长、没有圆形遮罩、默认theme=system、Settings额外跟随系统picker，均不一致。现preferences.theme持久化可保留，值统一映射light/dark；主题host应置于根部统一覆盖，避免每个屏独立动画。

## 8. 可复用 iOS Model / 服务接口清单

| 目标行为 | 已有入口与位置 | 还缺的UI/state |
|---|---|---|
| 账号/学校/学号/手机号 | account.profile、auth.session；OriginalFeatureAPI.profile(:5–30)，model.refresh(:115–168) | 原版无头像行布局、useCodeLoaded等专用完成态 |
| 改手机号 | sendAccountSMS(.newPhone)、updatePhone(:127–136)、auth.replaceSession（Profile:141） | 弹窗、11位gating、60s、当前号、成功关闭/原版toast |
| 两种改密码 | updatePassword/forgetPassword(:139–147)，purpose.forgotPassword=2 | 确认密码、模式切换、短信手机号输入、局部错误 |
| 码开关/候选/领取 | model.toggleCode/generateCode/claimCode(:305–324)；codeCandidate/createdAt/claimed/working | 后3位高亮、过期disable、blocked对话框、各忙态文案 |
| 寝室 | bindRoom(:302)，OriginalFormatting.roomKey/inSameRoom(:213–224)，nearby/ble.meters | 去重AlertDialog与TailEllipsis、解绑/跨寝室lastDevice收尾 |
| 卡排序/隐藏/跨页 | preferences.cardOrder/hiddenCards/settingsOrder/hiddenSettings(:35–65) | 原位四按钮编辑条、跨页时清hidden、枚举/legacy映射 |
| 通知/趋势 | preferences对应5项+trendEnabled；requestPermission(:34) | authorization读取、条件警告、折叠、banner开关语义 |
| 背景 | preferences.setBackground/resetBackground/opacity/blur/brightness/ThemeRGB(:70–102)，BackgroundPalette全文件 | 原版200dp预览、sample card、scope记忆、confirm、范围 |
| 日志 | model.logs/OriginalLogs.entries/clear/export | 85%对话框、计数、10sp、底按钮、拖条、临时导出 |
| 项目/版本 | 当前OriginalUpdateView.refresh(:294–301)只读release请求 | 统一只读metadata/cache/version比较服务；原版卡内版本列表 |
| Toast/错误 | model.message，model.report(:384–388)，根部toast(:32–39) | 为每个弹窗保留局部error，避免全局四秒toast替代原版局部提示 |

保留现有generation/session隔离、candidateWorking事务、防账号切换回调污染、transactionInProgress等业务保护；这次UI盘点不授权降低这些保护来机械复制Android实现疏漏。

## 9. 完整阅读记录与定位

以下文件已从头至尾阅读（上文路径前缀定义均为绝对根）：

- `A/ui/UserScreen.kt:1–1522`；`A/ui/UserSettingsCards.kt:1–280`；`A/ui/UserCardLayoutPolicy.kt:1–76`；`A/ui/UseCodeSection.kt:1–393`。
- `A/ui/CustomBackgroundScreen.kt:1–310`；`A/ui/LogViewerDialog.kt:1–191`；`A/ui/AppBackgroundLayer.kt:1–55`；`A/ui/TailEllipsisText.kt:1–97`。
- `A/ui/theme/Theme.kt:1–118`；`A/ui/theme/CircularRevealTheme.kt:1–167`。
- `A/utils/BackgroundManager.kt:1–140`；`A/utils/BackgroundState.kt:1–76`；`A/utils/PrefsHelper.kt:1–575`；`A/utils/ApkUpdater.kt:1–428`；`A/utils/Notifier.kt:1–446`；`A/utils/AppLogger.kt:1–170`；`A/utils/MD5Utils.kt:1–19`。
- `A/api/GithubApi.kt:1–175`；`A/data/AuthRepository.kt:1–80`；`A/model/DeviceModels.kt:1–266`。
- Android `app/src/main/res/drawable/ic_visibility.xml`、`ic_visibility_off.xml`全文件：24dp/24 viewport Material Filled路径；`app/src/main/res/xml/file_paths.xml`全文件：files/cache分享路径。
- `I/Views/OriginalProfileView.swift:1–308`（包括全部同文件settings/card editor/background/log/update/about/account/candidate/room子View）。
- `I/Models/OriginalPreferences.swift:1–103`；`I/Models/OriginalPlatformServices.swift:1–57`；`I/Models/OriginalBackgroundPalette.swift:1–74`；`I/Models/OriginalAppModel.swift:1–468`；`I/Models/OriginalAppModels.swift:1–302`；`I/Network/OriginalFeatureAPI.swift:1–206`。

另按依赖定位阅读（非声称整文件已读）：`A/ui/MainViewModel.kt:299–309,1505–1563,1698–1785,2076–2097`；`A/model/LoginModels.kt:134–152`（UseCodeData/ProjectInfo）；`A/api/SafeApi.kt:172–184,209–216,264–276`；`I/Views/OriginalRootView.swift:1–207`（本页theme/toast/nav/BaseCard/Background相关部分）；Android `app/build.gradle.kts:29,91–102`、`gradle/libs.versions.toml:12,35–42`。没有以未读的第三方Material3默认实现捏造精确组件内尺寸。

## 10. 实施验收时必须覆盖的状态组合

浅/深色各一套；home/shower无图/有图且不同调参；profile/settings默认与跨页迁移；所有卡隐藏/编辑半透明与边界上下箭头；有/无姓名学号；通知总关/权限拒绝/折叠/四子开关；使用码loading/无领取/开关/已领取/当天blocked/generate失败/领取失败/180s过期/claim提交；换号发送失败/60s/提交错误；改密码两模式/不一致/提交；寝室空/一条/重复多个设备同寝室/超长头省略；日志空/300条/拖条/清空/分享；版本checking/fail/latest/new、最近3/全部/展开单条；背景取消选择/重选重置参数/恢复取消与确认；主题动画中重复点击与动画前后状态保留。真实iOS不能支持的APK安装与Android常驻通知机制应列成平台行为适配项，不能把相应版面或检查状态整个删掉。
