# 附近水表真实名称自动识别

实现分支为 `fix/nearby-device-names-20261106`，从已有结算修复源码 `2b73da9` 创建。实现提交为 `b1b80860db9622ac33827ea5da284b2a97112386`。本次范围是名称解析、展示缓存、连接协调及首页名称提示。待用户统一发布时再集成分支、构建和发布。

## 根因

原 iOS 的 `nearby` 主要由扫描 UUID 的展示缓存填充。缓存未命中时，只有点击 `choose()` 才读取身份并查询台账，导致首次扫描只显示广播名。现在扫描发现即检查当前账号的持久化映射，未知设备进入串行识别队列，识别成功后按同一个 UUID 更新 `nearby`。

用户截图作为旧版名称问题的依据。截图里的结算记录和交易状态不在此次修复范围，原图也未加入仓库。

## Android 原版对照

固定参考为 Android `v3.1.0`，提交 `761ae9b51bb0168b5a4de63a91f5168328107234`。

| Android 源码及行为 | iOS 对应实现 |
| --- | --- |
| `utils/BluetoothScanner.kt` 从扫描结果直接取得 `device.address`，广播名先展示，默认扫描 5 秒 | `BleCentral.swift` 以 Core Bluetooth UUID 保持行身份；保留现有 iOS 的 6 秒扫描周期。未知 UUID 需要通过现有状态协议读取自报 MAC |
| `ui/MainViewModel.kt` 的 `addDevice()` / `fetchInfo()` 按 MAC 去重查询，响应后更新原索引的 deviceInfo | `NearbyMeterNameResolver.swift` 每轮对同 UUID 只做一次自动尝试；读取 0x23、请求台账、验证自报 MAC 与真实/派生台账 MAC 对应后，更新原 UUID 的显示元数据 |
| `onScanTimeout()` 只在扫描结束后按 RSSI 排序 | 保留 BleCentral 的扫描结束排序。名称更新只更新映射，未按名称、响应顺序或 RSSI 波动重排列表 |
| `data/DeviceInfoCache.kt` 为台账提供 60 秒 / 64 条短缓存 | 继续使用 `CampusDeviceLookup` / `CampusDeviceCache` 的现有去重与短缓存。额外保留 iOS 已有的账号隔离 UUID 展示缓存，24 小时 / 64 条，用于重启后的显示 |
| `data/BleShowerController.kt` 保留正在使用的连接供关阀使用 | iOS 名称识别只使用自己建立的临时连接；检测到现有用户连接、活跃用水、阀门待核实或正在处理的事务时延后自动识别 |

原版获取 MAC 不需要连接水表，iOS 因 Core Bluetooth 不公开 MAC，需要增加串行的身份读取。原版 fetchInfo 还会读取使用订单；本轮按用户范围只实现名称解析，自动流程的能力限定为身份读取和台账 GET，结果写入本地展示缓存。控制操作继续使用原有绑定和新鲜状态校验。 [BluetoothScanner](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/utils/BluetoothScanner.kt) · [MainViewModel](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/ui/MainViewModel.kt) · [DeviceInfoCache](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/data/DeviceInfoCache.kt) · [BleShowerController](https://github.com/yehu-imei/linyu/blob/v3.1.0/app/src/main/java/com/hualala/linyu/data/BleShowerController.kt)

## 队列与安全边界

1. 扫描期间即时显示有效缓存名称，缓存未命中先保留广播名和「名称待识别，点击识别」。自动 BLE 读取在扫描结束、首页可见且 App 位于前台后开始。
2. 串行处理扫描结束后的候选顺序。每个 UUID 每轮最多尝试一次。已失败的设备由手动点击或用户发起下一轮扫描重试。
3. 身份读取调用现有 `prepareConnection`、`exchange(0x23)` 和 `WaterProtocolIdentity.state`。沿用原有连接、断开及指令超时，不改变控制协议或交易超时。
4. 自动读取连接由独立 task/token 持有，完成或取消时释放。实际交易的 connect/reconnect 入口优先取消并等待该任务退出，避免迟到断开影响新连接。首页手动选择、扫码、刷新及操作入口也会先让自动连接退让。
5. 台账 GET 仍使用同账号的共享请求去重。同 MAC 的近期请求可复用。取消自动流程后，共享的只读 HTTP 请求可以独立结束，但迟到结果必须通过取消、账号代次及候选有效性检查才可更新界面。
6. 离开首页、进入后台、换账号或新扫描周期会取消/作废旧自动任务。超过 60 秒未发现的候选会停止自动处理，迟到台账结果也不再写入展示映射。Core Bluetooth 没有本轮发现列表的即时离场回调，因此实际离开只能通过失联、既有超时或发现时间失效识别。
7. 缓存新记录保存对应自报 MAC，并校验其与台账地址的对应关系。旧版已验证展示记录继续兼容读取。未再次读取身份前，iOS 无法即时知道一个有效缓存映射是否发生硬件身份变化；缓存不提供控制授权，实际控制仍重新核对水表状态。
8. 识别中显示有限任务状态；失败、取消或候选过期后恢复「点击识别」提示，不保留无限加载动画。

连接资源被用户保留、存在活跃/阀门待核实的用水记录时，自动 BLE 名称读取会延期，缓存命中仍可显示。未知设备、很弱的信号和较慢的服务端可能导致一轮扫描只能解析部分名称；等待过久的候选需重新扫描或手动识别。用户截图中的弱信号设备仍须在原水表附近验证。

## 诊断

每个候选使用独立的单调耗时 trace，阶段包括 `scan_discovered`、`cache_hit`、`identify_queued`、`ble_connect_started`、`identity_received`、`ledger_lookup_started`、`ledger_lookup_finished`、`display_name_updated` 和 `identify_failed`。

结果使用固定分类，如 timeout、disconnected、identity_mismatch、network_error、ledger_unavailable、cancelled、stale。诊断不写设备 UUID/MAC、原始报文、设备名称、手机号或认证凭据，也不附加服务端原始错误文本。

## 修改文件

- `LinYuIOS/BLE/BleCentral.swift` 增加可取消的只读身份连接及手动连接优先退让，增加扫描周期标识。
- `LinYuIOS/Models/NearbyMeterNameResolver.swift` 提供串行队列、去重、失效和诊断。
- `LinYuIOS/Models/OriginalAppModel.swift` 接入缓存、可见性、会话隔离及手动入口协调。
- `LinYuIOS/Models/OriginalAppModels.swift` 为展示缓存保留可选的观测 MAC，复用台账地址校验。
- `LinYuIOS/Views/OriginalHomeView.swift` 实时显示名称和有限识别状态。
- `LinYuIOSTests/NearbyMeterNameResolverTests.swift` 增加 14 项 Mock 回归用例。

`WaterTransactionEngine.swift`、`WaterContracts.swift`、`TransactionManager.swift`、网络、认证、主题和用水页面均与分支基线保持一致。OriginalAppModel 的交易入口仅增加取消名称读取的连接让路调用及会话代次检查，原交易处理顺序和状态转换保留。

## 验证结果

已完成以下本地检查。

- 六个变更 Swift 文件通过 tree-sitter Swift 语法树检查，没有解析错误。
- `git diff --check` 通过。
- 对照基线核实交易引擎、协议、认证、网络、主题、构建配置和工作流文件未修改。

以下 14 项自动化用例已添加，当前尚未执行。

| 用例 | 覆盖 |
| --- | --- |
| UnknownSameNameMetersResolveSeriallyByObservedIdentityAfterScan | 首次扫描、多台同名水表、串行及按身份更新 |
| ValidCacheHitDoesNotConnectOrQueryLedger | 缓存命中即显示，零自动连接/台账查询 |
| RepeatedDiscoveryCoalescesOneAttemptAndLeavesManualRetryAvailable | 重复发现、弱信号、连接超时及每轮有限尝试 |
| ExplicitNewScanMayRetryAnEarlierConnectionTimeout | 用户明确刷新后可再次识别 |
| LedgerFailureStopsLoadingAndDiagnosticDoesNotIncludeErrorContents | 台账失败、加载恢复和日志脱敏 |
| MismatchedLedgerCannotNameAnotherPhysicalMeter | 不套用另一台设备名称 |
| OriginalDerivedMACMappingIsAcceptedWithoutGuessingName | 原版派生 MAC 对应关系 |
| ExpiredPresenceDuringLedgerRequestDoesNotPublishStaleResult | 查询期间离场/发现信息过期 |
| ManualPreemptionCancelsBeforeLedgerAndPreventsLateNameUpdate | 手动优先取消及迟到结果抑制 |
| LeavingPageDuringLookupSuppressesItsResult | 页面切换后的任务取消 |
| TransactionOrActiveConnectionDefersQueuedDevices | 调度器禁用期间不发起识别 |
| MissingAndStaleDevicesDoNotReceiveBackgroundConnections | 候选移除或过期 |
| AccountResetIgnoresLateOldOwnerLookup | 账号切换后的结果隔离 |
| VerifiedCacheSurvivesRestartIsAccountScopedAndRejectsChangedIdentity | 重启恢复、账号隔离、TTL 和新观测身份不一致失效 |

当前 Windows 环境没有 Swift 编译器、Xcode 或 iOS 模拟器。语法树检查不等同于 Swift 类型检查或 XCTest 通过。上述用例的运行结果、真实 Core Bluetooth 连接取消/回调时序、跨页面切换、交易抢占、两台弱信号设备的自动命名和缓存重启表现仍需后续 macOS 测试与真机验收。本次没有新增 IPA、Actions 运行或 GitHub Release。
