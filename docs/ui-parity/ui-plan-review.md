# UI parity builder check（只读审查）

结论：源码驱动 SwiftUI、独立 `ui/android-parity`、保留原协议与交易实现的方向可执行；目前有 6 项需在相应实现前补齐的契约/验收阻塞。均可由实现者直接解决，无需重新设计或再次向用户确认。

1. **共享弹窗缺少不可取消/处理中策略。** spec:27 只有 `LinYuModal(isPresented:content:)`，不足以表达开启中、自动关闭、挤号不可外点关闭，以及换号/改密仅提交中锁定关闭。请发布 `dismissPolicy` 或 `canDismiss`、`onDismiss` 与模态优先级/替换语义；同时验证 scrim 吃掉点击、VoiceOver 焦点与下层控件不可触发。按钮由各弹窗持有即可。

2. **“调用现有模型、保持业务”尚不能实现已经盘点的状态。** `OriginalAppModel.swift:193–205` 的 choose 会连接 BLE、读状态、强制持久化 Bluetooth 并关联；`:185–186` 挤号立即 expireSession；`AuthManager.swift:59–75` 退出仅检查 transactionInProgress。原 UI 要求只查详情、挤号确认后退出并保留恢复线索、活动订单禁止主动退出。请把这些明确列为表示层/会话门禁适配项，提供只读设备查询、可观察启动进度/归属/挤号事件/自动结算状态及统一 logout gate；冻结 API、BLE 帧与交易引擎。不能为显示原 UI 而在 View 中复制网络/事务。当前 `OriginalFinishNotice` 仅 id/title/duration，无法显示结算中→实际金额状态，也需只读适配。账单单笔确认应直接解析原始金额并检查 finite，不可复用 `CampusUnpaidBill.amount` 的失败回退 0；批量已有 `OriginalStartFailure.total` 可复用。

3. **根路由与共享主题签名仍缺重要事件。** plan:64 把 profile 路由签名留至集成前；但进入设置、跨页迁移后的卡片开次级页面、用水页收起、登录后重置首页、未登录通知/Widget 深链暂存与登录后消费、全局挤号互斥需同一协调者。请先固定 route enum/binding 和模态事件接口，再开始页组，避免每页各建 NavigationStack/sheet。深链适配保留现有 owner/nonce 校验，不能把暂存路由变成未验证 start/stop 执行。`LinYuThemeHost` 还需显式接收点击 origin/触发事件、动画重入锁和当前 home/shower scope；否则仅观察 preferences 无法忠实复刻揭示中心与分作用域提色。

4. **视觉 fixture 约束正确，构造路径尚未闭合。** `OriginalAppModel.init()` 会调用 accountChanged、注册通知回调；已有会话时会自动 refresh，并订阅 publishSnapshot（持久化 Widget/通知）。只用 test-only 标志并给该真实模型塞假数据不满足“不认证、不持久化、不发网络/设备/扣款”。请在截图任务前确定纯 presentation snapshot + no-op action facade，或完整注入隔离依赖/内存 store，并用断言证明 0 API/transport/Keychain/UserDefaults/widget/notification 写入。Release target 不包含 fixture 源文件；不是仅靠运行时开关隐藏。

5. **完整视觉复刻目前只有验收愿望，缺可核验清单与基准。** spec:51 要求每 route/state×小大屏×浅深色，但 inventory 中已有大量局部状态，尚未见逐项截图 ID、Android 对照来源、iOS viewport/字号/语言/键盘/安全区条件、结果与差异列。Task 1 的映射表须包含全局会话/通知入口/扫码权限拒绝与启动失败/自动结算等状态，不能只按页面打勾。先列出 Android 真 APK 可安全捕获的状态；缺 APK 图时保留“源码核对、视觉未证”状态，不能据 preview 或编译通过写为完整复刻。补统一显式 typography/行高/fallback 与 TailEllipsis 原算法；仅 palette/card/button 不足以避免各页采用 iOS 默认字体。

6. **WidgetKit 的交付边界尚无具体责任项。** spec:47 说单独评估、plan 全局又称全部界面含 WidgetKit；七项任务没有明确原 Android widget families/各数据与空态/入口动作到 iOS 对照和证据。请在映射与验收增加平台适配行及责任任务，说明 LiveContainer 包排除扩展、标准 target 的实际支持范围。无法支持的 Android 尺寸/常驻扫描照实记录，但不漏掉对应入口或把待评估标为已完成。

范围核对：登录、首页、扫码、共享扣款/设备弹窗、账单/趋势、使用页、个人/设置/背景/日志/更新均已列入；未发现有意删页或重新设计。全局会话、深链及 Widget 属于上面需显式落到任务的遗漏。内部七个工程任务可以嵌入用户六阶段执行，进度文档应显示对应关系，避免把“阶段 6 验证/交付”误写成另一套用户流程。

依据：完整阅读所指 spec、plan、`work/ui-inventory-home-auth.md`；额外核查当前 iOS `OriginalAppModel`、`AuthManager`、`OriginalPreferences`、`OriginalAppModels` 及根/个人页相关实现。未修改产品、测试、计划；未执行网络写入，未宣称已有运行时视觉验证。
