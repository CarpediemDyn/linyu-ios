# LinYu Android v3.1.0 与 iOS 业务对照

Android 基准固定为 `v3.1.0`（`a650066`）。另核对了远端主分支 `5bdfc5171884eb50759c833eaa3ce5bd28cfb680`。表内 Android 路径相对于 `app/src/main/java/com/hualala/linyu/`，iOS 路径相对于仓库根目录。[v3.1.0](https://github.com/yehu-imei/linyu/tree/v3.1.0) · [上游主分支对照](https://github.com/yehu-imei/linyu/compare/v3.1.0...5bdfc5171884eb50759c833eaa3ce5bd28cfb680)

| 模块 | Android v3.1.0 路径和行为 | iOS 路径和行为 | 已证实差异、影响及处理 | 验证 |
| --- | --- | --- | --- | --- |
| 登录、注册、验证码、会话失效 | `ui/LoginViewModel.kt`、`data/AuthRepository.kt`、`api/NetworkModule.kt`、`utils/PrefsHelper.kt`、`ui/MainViewModel.kt`。短信注册登录共用接口，密码签名，缓存会话，心跳识别挤号。 | `LinYuIOS/Views/AccountView.swift`、`LinYuIOS/Models/AuthManager.swift`、`LinYuIOS/Network/QzxyAPI.swift`、`LinYuIOS/Models/OriginalAppModel.swift`。共用短信接口，Keychain 存会话，前台心跳。 | 平台存储和前台调度不同。iOS 在交易执行期间延后会话清理，设备恢复按账户隔离。服务端挤号信号及锁屏恢复需要联测。 | `QzxyAPITests` 和登录 UI smoke 覆盖登录合同、单次提交、错误和主页恢复。 |
| BLE 扫描、连接、重连 | `utils/BluetoothScanner.kt`、`ble/BleController.kt`。按广播名识别、Android 扫描地址连接、订阅通知就绪。扫描默认 5 秒。 | `LinYuIOS/BLE/BleCentral.swift`。Core Bluetooth UUID 选连接，订阅特征通知后发送指令，隔离跨连接回调。 | 平台需用 UUID。iOS 现有 6 秒扫描和就绪连接复用与固定基准不同，现场发现率与弱信号连接耗时待验证。关阀后两次连接机会与 500 ms 回退按原版路径执行。 | 核心 Mock 验证连接代次、重连后采集、断开前凭据持久化。 |
| 设备查询与缓存 | `ui/MainViewModel.kt`、`data/DeviceInfoCache.kt`。可直接从扫描 MAC 查台账，短缓存。 | `LinYuIOS/Models/OriginalAppModel.swift`、`LinYuIOS/Models/OriginalAppModels.swift`、`LinYuIOS/Network/OriginalFeatureAPI.swift`。先读自报地址，再查台账，短缓存与请求去重。 | 平台需要先解析 BLE 状态。iOS 额外保存账户隔离的 24 小时 UUID 展示缓存，控制时另读状态并验证；原版扫描阶段可识别更多未缓存水表。 | `OriginalFeatureAPITests` 覆盖原始和派生地址、缓存过期、并发合并、重启及账户隔离。 |
| 设备身份和状态码 | `ble/BleController.kt`、`data/BleShowerController.kt`。v3.1.0 读取至少 31 字节的状态回包，0 空闲、1 出水、3/6 待结算。 | `LinYuIOS/BLE/BleDeviceState.swift`、`LinYuIOS/Transactions/WaterTransactionEngine.swift`。长回包与 28 字节短布局，UUID 与自报 MAC 同台账核对。 | iOS 短布局对应后续上游修复。对其他状态码要求核实，原版对非零且本地有活跃订单的情况更宽松。这样可以避免未知状态被提升为确认开启。 | `WaterTransactionTests` 验证长短布局、设备 MAC、连接代次和 3/6。 |
| 费率和开阀确认 | `data/BleShowerController.kt`、`data/BleSignBuilder.kt`、`api/NetworkModule.kt`。以设备随机数签名，费率下发后以 0x21 的 0x80 确认。云设备由 `data/ShowerController.kt` 轮询确认。 | `LinYuIOS/Transactions/WaterTransactionEngine.swift`、`LinYuIOS/Transactions/CloudShowerController.swift`、`LinYuIOS/Network/QzxyAPI.swift`、`LinYuIOS/Security/KailuSigner.swift`。 | 主指令和确认语义对应。iOS 增加写入前日记与连接代次检查，云端未知请求跨重启先查状态。空闲设备仍要求用户明确发起下一次开阀。 | 核心及 HTTP 夹具覆盖签名字段、真实 ACK、失败、超时和重试核对。 |
| 正在用水时恢复 | `ui/MainViewModel.kt`、`data/BleShowerController.kt`。持有本地活跃订单才能恢复计时与关阀。 | `LinYuIOS/Transactions/WaterTransactionEngine.swift`、`LinYuIOS/Models/OriginalAppModel.swift`。同一水表的确认开启订单恢复，关阀或开阀未知记录单独提供核实入口。 | 修复交易未归档即被当作活跃订单的问题。iOS 既有保护仍要求当前账户与绑定匹配。 | 核心 Mock 覆盖恢复时无重复开阀、陌生运行设备拦截，iOS 集成测试覆盖状态显示来源。 |
| 正常和异常关阀 | `data/BleShowerController.kt`、`ui/MainViewModel.kt`。0x22 ACK 确认，未确认留使用页，部分结算退出使用页并清活跃列表。 | `LinYuIOS/Transactions/WaterTransactionEngine.swift`、`LinYuIOS/Models/OriginalAppModel.swift`、`LinYuIOS/Views/OriginalShowerView.swift`。 | 本轮按原版区分关阀事实和结算结果，关阀失败留页，确认关闭后退出。重新连接读状态后，历史已关闭订单没有资格关闭正在使用的设备。 | iOS 集成测试覆盖关阀 ACK 失败留页、确认后上传失败回首页。 |
| 消费采集、上传与响应 | `data/BleShowerController.kt`、`data/BleSignBuilder.kt`、`api/NetworkModule.kt`。重连获取新状态和随机数，0x85、原始 payload 小写签名、服务器结果码。 | `LinYuIOS/Transactions/WaterTransactionEngine.swift`、`LinYuIOS/Network/QzxyAPI.swift`、`LinYuIOS/Security/KailuSigner.swift`。 | iOS 先校验至少 42 字节及 0x80，处理 0/206/209 和 data；已有上传意图但响应未知时改用只读核实，避免重复上传及对未知已记账订单上报失败。 | 核心和 Qzxy Mock 覆盖格式、完整 payload、签名、明确拒绝、结果未知及精确账单匹配。 |
| 写回及遗留订单 | `data/BleShowerController.kt`、`ui/MainViewModel.kt`。解密 clData，0x86 清账，3/6 先补结算再让用户重新开阀。 | `LinYuIOS/Transactions/WaterTransactionEngine.swift`、`LinYuIOS/Transactions/TransactionManager.swift`。持久保存收据和写回数据。 | 修复 3/6 复用记录时保留旧开阀标记、空闲时隐藏有价值历史的问题。收据已存在时只恢复写回。仅凭正额同订单账单和空闲可归档账单核实结果，仍在 3/6 且缺 clData 时保留待清账。原版部分写回失败可仍返回记账完成。 | 核心 Mock 覆盖 3/6、写回失败、丢 ACK、历史保留、重启后重复核实时只读。 |
| 余额、账单、预扣及欠费 | `ui/MainViewModel.kt`、`data/SettlementEngine.kt`、`api/NetworkModule.kt`。账户信息、分月账单与结算探测，明确拒绝后进入补扣。 | `LinYuIOS/Models/OriginalAppModel.swift`、`LinYuIOS/Network/OriginalFeatureAPI.swift`、`LinYuIOS/Views/OriginalWalletView.swift`、`LinYuIOS/Transactions/CloudShowerController.swift`。 | iOS 主页出现后调度缓存读取及网络同步。BLE 未知上传核对使用精确订单及正额账单，排除原云端探测使用的按时间兜底和零金额占位。真实账单回填时机和单位仍需比对。 | HTTP 夹具覆盖账单单位、跨设备、欠费确认和未知结果。 |
| 计时、自动关停和通知 | `ui/MainViewModel.kt`、`service/ShowerWatchService.kt`、`utils/Notifier.kt`。持久开始时间、云端自动关停，前台服务和通知操作。 | `LinYuIOS/Views/OriginalShowerView.swift`、`LinYuIOS/Transactions/CloudShowerController.swift`、`LinYuIOS/Models/OriginalPlatformServices.swift`。SwiftUI 计时，云端按服务端状态确认，UserNotifications 动作。 | iOS 受后台挂起限制。使用中通知与 Widget 从同一运行订单列表生成，关阀或未知时清除旧的待送达和已送达使用中通知。系统通知实际呈现需真机验证。 | 云端轮询、自动关停数据和共享状态输入已有 Mock 测试。 |
| Widget 与 App 状态 | `widget/LinYuWidgetProvider.kt`、`widget/WidgetActions.kt`、`service/WidgetBleService.kt`。Android 小组件可经服务直接控制。 | `LinYuWidgets/LinYuWidgets.swift`、`Shared/LinYuWidgetSnapshot.swift`、`LinYuIOS/Models/OriginalAppModel.swift`。WidgetKit 读取账户快照，链接交给 App。 | 平台及签名适配。LiveContainer 包采用 App target，Widget 扩展属于普通签名发行。快照与首页共用已确认开启语义；普通签名 Widget 安装和刷新须实机验证。 | iOS 集成 Mock 验证关阀前后及 ACK 未确认时的快照。 |
| 多设备与互斥 | `ui/MainViewModel.kt`、`data/ShowerController.kt`。多个设备活跃订单，单一当前 BLE 控制会话。 | `LinYuIOS/Transactions/WaterTransactionEngine.swift`、`LinYuIOS/Transactions/CloudShowerController.swift`、`LinYuIOS/Models/OriginalAppModel.swift`。持久化按水表和账户区分，BLE 串行。 | iOS 的页面操作锁覆盖当前命令，旧闭阀订单无法操作下一笔使用。多台实体水表交替及后台切换待测。 | 核心及云端 Mock 覆盖两台设备、历史收据、账户隔离和无重复扣费请求。 |
| 后台、重启、崩溃、退出 | `utils/PrefsHelper.kt`、`ui/MainViewModel.kt`、`service/ShowerWatchService.kt`。恢复活跃记录，挤号保存关键数据，显式退出区分恢复需求。 | `LinYuIOS/Security/KeychainStore.swift`、`LinYuIOS/Transactions/TransactionManager.swift`、`LinYuIOS/Models/OriginalAppModel.swift`、`LinYuIOS/Views/OriginalProfileView.swift`。 | 日记保留跨进程结算事实，旧 `uploading` 转 `uploadUnknown`。有阀门风险时拦截用户主动退出，已关闭交易可在原账户重新登录后恢复。系统终止、LiveContainer 钥匙串和实体断线需要联测。 | 核心 Mock 覆盖重建引擎、恢复记录、写回重试和账户边界。 |
| 页面跳转、错误和交互 | `ui/MainScreen.kt`、`ui/DeviceDetailDialog.kt`、`ui/ShowerScreen.kt`、`ui/UserScreen.kt`、`ui/WalletScreen.kt`。使用中、关闭失败、部分结算各有返回和提示。 | `LinYuIOS/Views/OriginalRootView.swift`、`LinYuIOS/Views/OriginalHomeView.swift`、`LinYuIOS/Views/OriginalDeviceDialogs.swift`、`LinYuIOS/Views/OriginalShowerView.swift`、`LinYuIOS/Views/OriginalProfileView.swift`。 | 本轮修复首页、详情、用水页和退出时的状态语义。恢复入口是 iOS 交易日记的界面映射。完整视觉交互另有映射与验收清单。 | 回归验证返回首页及核实入口。逐屏验收参见 [已有 UI 映射](ui-parity/ANDROID_IOS_MAP.md)。 |

已证实的上游变化包括拆出状态解析器、增加 28 字节布局、区分实际连接地址与台账地址、加严消费回包检查，以及精简用户反馈和从文档读取版本说明。当前 iOS 费率接口地址选择仍对应 v3.1.0 的 `realMac` 优先规则。后续迁移至主分支规则时应先使用带 `realMac` 的真实设备和接口样本验证。[上游 BLE 控制器](https://github.com/yehu-imei/linyu/blob/5bdfc51/app/src/main/java/com/hualala/linyu/data/BleShowerController.kt)

用户现场缺少原始 BLE 与服务器日志，触发该次超时的网络环节、实际水表何时从 3/6 返回 0、以及缺少 clData 时服务器是否有可用的凭据查询，仍待核实。原版源码和现有 API 夹具提供了账单读取路径，账单能证明对应记账，设备清账仍依赖真实状态或原有有效写回凭据。


## 修复提交和验证结果

- `38daa66` 区分阀门与结算，恢复旧交易、拦截不确定上传的重复发送，调整首页、详情、使用页与退出入口。
- `067ec0e` 增加 Mock 登录、BLE 和网络集成验证，核对精确订单号账单，清除过期的待发送和已发送使用中通知。

SwiftPM 核心 33 项在 Linux 和 macOS 通过。iOS 模拟器 112 项、打包 8 项通过。iOS 集成验证覆盖关阀 ACK 失败时留在使用页、关阀成功但上传超时返回首页、首页与 Widget 快照的运行订单一致，以及再次恢复使用只读账单路径。自动化使用 Mock BLE 和网络。[Linux 核心测试](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42068484260) · [iOS 测试和 IPA 构建](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42068572440)

`LinYu-LiveContainer.ipa` 为 **v0.4.2（构建 6）**，源提交 `067ec0ebeed6c0a426711a1c39cf2102721f508b`，iPhoneOS arm64，最低 iOS 16.0。GitHub Actions 完成签名和严格验签。下载后核对了 SHA-256 和全部 7 个包成员。

`SHA-256 fb38dbff62329443fb46c5c9b124aea025dbf5edc69ffc08d3d091e4d0f8b6ea`

真机验收还包括实际水表关阀、重连后采集及写回、服务器超时后的订单号和账单回填、强退后恢复、同账户重新登录，以及 iOS 通知和普通签名版 Widget 的实际刷新。[GitHub IPA 制品](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42068572440/artifacts/13435580545)
