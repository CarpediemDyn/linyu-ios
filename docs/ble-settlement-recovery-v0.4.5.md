# LinYu iOS 0.4.5 蓝牙结算恢复验收

修复分支 `fix/ble-settlement-recovery` 从稳定版 `afde230` 分出。0.4.5 的构建号为 9，产品源码提交为 `c6d6c3302aa92161cd6ff48656a671cbbcf47de5`。

## 根因和行为

| 问题 | 根因 | 修复后的行为 |
| --- | --- | --- |
| 待结算时长累计 | 用水视图始终以当前时间减去开阀时间，恢复逻辑还用交易阶段推断阀门已关闭 | 持久化有效关阀 ACK 或身份验证后的设备关闭读数及观测时间。仅 ACK 能确定原订单结束时刻。待结算页面冻结已确认用水时长，旧单没有可靠结束时间时显示「上次用水时长待核实」 |
| 远离设备无法查账 | 恢复先连接蓝牙，再查询服务器账单 | 上传结果未知时先通过登录账户的账单只读接口核实。匹配优先使用订单号，并核对可得的消费时间和设备 SN。零金额、未出现、歧义或冲突的账单继续保留未知状态 |
| 阶段不清、返回困难 | 关阀、查账和设备清账共用进度，失败后提示容易被首页切换盖掉 | 显示查账、连接、读取、上传、写回阶段。恢复失败后保留结果和重试入口，可返回首页。初次关阀已确认时会退出使用页，关阀结果未知时保留核实入口 |
| 旧单误操作或重复扣费 | 旧版日志有可能丢失原上传阶段，结算记录还可能碰到同一水表的新会话 | 仍保留历史订单、原始消费数据、回执和错误。旧版曾被标记为已替代且仍带消费数据的记录进入只读核实。跨设备独立处理，已有较新本地使用记录时停止旧记录的设备操作。清账重试须核对水表消费数据与已保存记录 |

## 与 Android v3.1.0 的对照

- 原版 BLE 顺序是 `0x22` 确认、断开重连、读取状态和随机数、`0x85` 采集、上传、`0x86` 写回。iOS 保留该顺序、现有签名、成功码和重连重试策略。对持有已接受回执的历史重试，iOS 会先确认水表当前的消费数据与日志相同，再允许使用保存的写回凭据。 [BleShowerController.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/data/BleShowerController.kt#L292)
- Android 收到 `PartialSettlement` 后退出使用页并清除活跃计时。iOS 同样退出已确认关阀的活跃流程，同时保留单独的恢复入口、物理证据和可信结束时间。 [MainViewModel.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/ui/MainViewModel.kt#L1230)
- Android 在状态 3/6 尝试补结算。iOS 对历史已知上传结果不明的订单加了只读对账，只有可安全证明属于当前订单、且没有未知上传的路径才继续设备补结算。月账单能证明的内容不包括 `clData`，所以设备仍有遗留数据且没有写回凭据时会保留待清账。 [BleShowerController.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/data/BleShowerController.kt#L170)
- `ShowerController.kt` 的云端关阀是独立路径，本次修复聚焦 BLE。 [ShowerController.kt](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/data/ShowerController.kt#L294)

## 文件范围

- 交易、计时与迁移使用 `WaterContracts.swift`、`WaterTransactionEngine.swift`。
- 只读对账使用 `QzxyAPI.swift`、`OriginalFeatureAPI.swift`、`OriginalAppModels.swift`。蓝牙附近判断在 `BleCentral.swift`。
- 恢复进度和页面使用 `OriginalAppModel.swift`、`OriginalShowerView.swift`、`OriginalHomeView.swift`、`OriginalDeviceDialogs.swift`。
- 测试在 `WaterTransactionTests.swift`、`QzxyAPITests.swift`、`SettlementRecoveryTests.swift`，模拟器的离线双水表场景由 `LoginFeedbackFixture.swift` 提供。

## 自动化验收

最终 GitHub Actions 在 2026 年 11 月 6 日通过 43 项 SwiftPM 核心测试、125 项 iOS 单元及布局测试、7 项 UI 测试和 8 项打包测试。125 项 iOS 测试中包含再次运行的 43 项交易测试。所有交易操作均使用 Mock BLE 和 Mock API。物理设备包采用 LiveContainer 的 ad-hoc 签名，CI 的严格签名检查已通过。 [最终构建](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42154843612)

| 场景 | 自动化证据 |
| --- | --- |
| 正常开阀和关阀 | 原有开阀 ACK 和完整关阀采集测试通过 |
| 关阀后重连/状态读取失败 | `testCloseACKFreezesDurationBeforeReconnectAndSurvivesRelaunch` 验证时间和关阀证据仍落盘，忙状态结束 |
| 消费采集超时 | `testClosedACKPersistsAcrossRelaunchBeforeCollection` 验证重启后恢复且只发送一次关闭 |
| 上传超时但服务端已记账 | `testLostUploadResponseChecksAccountBeforeAttemptingBluetooth` 验证先查账、离线保留已记账结果 |
| 设备不在附近 | 核心和 UI 测试均使用不可用水表，验证可查账、提示靠近原设备且恢复按钮可再次点击 |
| 447 与 450 两笔历史记录 | `testLegacyOrdersOnDifferentMetersStayIsolatedWhileCheckingBillsOffline` 分别保留订单、消费时间、原始数据和账单结果 |
| App 重启 | 重新建立交易引擎并从序列化日志恢复，保留关闭证据和消费数据 |
| 旧版本迁移 | `testLegacyUploadUnknownDoesNotProvePhysicalClosure` 和 `testLegacySupersededChargeWithSavedConsumptionIsNeverReplayed` |
| 失败后结束加载 | 集成测试检查 `working`、`settlingBluetooth`、`bluetoothSettlementProgress`，UI 测试确认恢复按钮重新可用 |
| 待结算时长停止增长 | 使用相隔 1141 分钟的时间点比较固定时长，旧单 UI 显示时长待核实 |
| 已记账不重复上传/写回 | 原有写回失败恢复和新消费数据比对测试通过 |
| 缺少可靠关阀证据 | 旧单恢复后保持阀门未知，UI 测试核实标题与账单核实状态分别显示 |
| 跨账号和新旧订单隔离 | 新测试覆盖费率请求尚未写入、账号切换和同水表较新消费，阻止旧记录控制或上传 |
| 账单匹配冲突 | 测试覆盖同订单号多行、设备 SN 不同、时间不同、零金额、缺失及账单 ID 与订单号冲突 |

先前的复现构建在两个新增测试上如预期失败，证实旧逻辑会误判阀门已关闭、蓝牙失败会阻止账单核实。后续编译和 UI 自动化发现的组件参数及返回按钮标识问题已修正，最终全套测试通过。 [基线复现](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42153220416)

## 提交与制品

- `5c1fbde` 增加基线复现测试。
- `d752ee3` 保存关阀证据、可靠时间，调整账单优先的恢复和界面。
- `9e4c701` 保留旧记录恢复性质，减少不必要的蓝牙访问。
- `479f2ec` 保护仅费率阶段及跨账户水表订单。
- `c6d6c33` 保留旧版上传不确定性，补齐新旧订单隔离、账单匹配和可访问性修复。

构建的 `LinYu-LiveContainer.ipa` 为 iOS 16.0 及以上 arm64 iPhone/iPad 通用包，版本 0.4.5、构建 9、大小 4,422,225 字节。下载后已验证源码提交、ZIP CRC、全部 7 个清单文件的 SHA-256、真机 Mach-O 类型和版本字段。IPA SHA-256 为 `baac34b7ae1f7136fd1582d9809e036f41b9da9a6252e4895aa28d1b9bb61f2c`。 [下载 IPA 制品](https://github.com/CarpediemDyn/linyu-ios/actions/runs/42154843612/artifacts/13473054957)

## 真机待验证

447 和 450 的实际账单、阀门状态以及设备写回仍须在原 iPhone 上按账户分别核实。使用同一 LiveContainer 应用数据升级，以保留旧交易日志。可以离开水表先查询账单。需要设备核实时，靠近原水表并扫描。如果账单已确认且水表已空闲，可以归档。如果设备仍保留消费数据而应用没有服务端写回凭据，订单继续留在恢复列表。
