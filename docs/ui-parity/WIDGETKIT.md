# Android 桌面组件的 iOS 等效方案

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
