import SwiftUI

@MainActor struct OriginalDeviceDetail: View {
    @ObservedObject var model: OriginalAppModel
    let device: CampusDevice
    let onStart: (CampusDevice) -> Void
    let onDismiss: () -> Void
    private var bluetoothOrder: WaterTransaction? { model.activeBluetooth.first { $0.binding.device.deviceId == device.deviceId } }
    private var bluetoothRecovery: WaterTransaction? {
        (model.unconfirmedBluetooth + model.unsettledBluetooth).last {
            $0.binding.device.deviceId == device.deviceId && !$0.idleConfirmed
        }
    }
    private var cloudOrder: CloudActiveOrder? { model.currentCloud.first { $0.snCode == device.snCode } }
    private var active: Bool { bluetoothOrder != nil || cloudOrder != nil }
    var body: some View {
        OriginalDeviceDetailContent(device: device, isActive: active, busy: model.isBusy,
                                    availability: model.selectedDeviceAvailability,
                                    recovery: active ? nil : bluetoothRecovery?.usageState,
                                    settlementRecovery: bluetoothRecovery?.isSettlementRecovery == true,
                                    bluetooth: Binding(get: { model.usesBluetooth(device) }, set: { model.setBluetooth($0, device: device) }), onConfirm: {
            if let bluetoothOrder { model.showShower = bluetoothOrder.id; onDismiss() }
            else if let cloudOrder { model.showCloudShower = cloudOrder.snCode; onDismiss() }
            else if let bluetoothRecovery { model.showShower = bluetoothRecovery.id; onDismiss() }
            else { onDismiss(); onStart(device) }
        }, onDismiss: onDismiss)
    }
}

struct OriginalDeviceDetailContent: View {
    @Environment(\.linYuColors) private var colors
    let device: CampusDevice
    var isActive = false
    var busy = false
    var availability: OriginalDeviceAvailability = .idle
    var recovery: WaterUsageState? = nil
    var settlementRecovery = false
    var bluetooth: Binding<Bool>? = nil
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    private var typeTitle: String { device.isDrinkingWater ? (device.isHotWater ? "饮水（热水）" : "饮水（冷水）") : device.deviceName.hasPrefix("洗手台") ? "洗漱" : "沐浴" }
    private var typeName: String { device.isDrinkingWater ? "饮水机" : device.deviceName.hasPrefix("洗手台") ? "洗手台" : "热水器" }
    private var canUse: Bool { (isActive || recovery != nil || (availability != .occupied && availability != .running)) && !busy }
    private var buttonTitle: String {
        if isActive { return "恢复使用" }
        if settlementRecovery || recovery == .settlementPending { return "继续核实结算" }
        if recovery == .unconfirmed { return "核实状态" }
        if availability == .occupied { return "他人使用中" }
        if availability == .running { return "设备使用中" }
        return device.isDrinkingWater ? "开始接水" : "开始使用"
    }
    var body: some View {
        LinYuDialogCard {
            VStack(spacing: 24) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) { Text(device.emoji).font(LinYuType.font(22)); Text(typeTitle).font(LinYuType.font(22, weight: .bold)) }
                    Text(device.displayName).font(LinYuType.font(15, weight: .medium)).foregroundStyle(.gray).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                VStack(spacing: 0) {
                    OriginalDeviceDetailLine(label: "类型", value: typeName)
                    OriginalDeviceDetailLine(label: "SN 码", value: device.snCode)
                    OriginalDeviceDetailLine(label: "MAC 地址", value: device.macAddress)
                    OriginalDeviceDetailLine(label: "预扣金额", value: device.withholdMoney.map { "¥" + OriginalFormatting.money($0) } ?? "金额未知")
                    OriginalDeviceDetailLine(label: "状态", value: isActive ? "使用中" : recovery == .settlementPending ? "已关阀，待结算" : recovery == .unconfirmed ? "阀门状态待核实" : availability.label)
                    if device.needsBluetoothControl {
                        Text("此设备通过手机蓝牙直连控制：开启后请留在设备旁，走远会断开连接、无法关闭。")
                            .font(LinYuType.font(13)).lineSpacing(5).foregroundStyle(colors.textSecondary).padding(.top, 10)
                    }
                    if let bluetooth, !isActive, !device.needsBluetoothControl {
                        DisclosureGroup("连接方式") {
                            Toggle("蓝牙直连设备", isOn: bluetooth).disabled(busy)
                        }.font(LinYuType.font(13)).tint(colors.accent).padding(.top, 10)
                    }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("取消", action: onDismiss).buttonStyle(.plain).foregroundStyle(colors.accent).padding(.horizontal, 12)
                    Button(buttonTitle) { if canUse { onConfirm() } }.buttonStyle(LinYuButtonStyle()).disabled(!canUse)
                }
            }
        }.accessibilityIdentifier("linyu.device.detail")
    }
}

private struct OriginalDeviceDetailLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(LinYuType.font(14, weight: .bold))
            Spacer(minLength: 12)
            Text(value).font(LinYuType.font(14)).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.padding(.vertical, 4)
    }
}

@MainActor struct OriginalStartFailureView: View {
    @ObservedObject var model: OriginalAppModel
    let failure: OriginalStartFailure
    let onDismiss: () -> Void
    @State private var confirming = false
    private var bills: [CampusUnpaidBill] { failure.bills(in: model.unpaid) }
    private var total: Double? { failure.total(for: bills) }
    var body: some View {
        Group {
            if confirming {
                OriginalDeductConfirmDialog(amount: total, detail: "共 \(bills.count) 笔", busy: model.isBusy, onConfirm: {
                    guard !bills.isEmpty, let amount = total, amount.isFinite, !model.isBusy else { return }
                    let confirmed = bills
                    let owner = model.auth.session?.ownerScope
                    confirming = false; onDismiss()
                    Task {
                        guard owner != nil, model.auth.session?.ownerScope == owner,
                              model.unpaid.filter(\.isDeductible) == confirmed, !model.isBusy else { return }
                        await model.deductAll()
                    }
                }, onDismiss: { confirming = false })
            } else {
                OriginalStartFailureContent(message: failure.message, bills: bills, busy: model.isBusy,
                                            onDeduct: { confirming = true }, onDismiss: onDismiss)
            }
        }.onChange(of: failure.id) { _ in confirming = false }
    }
}

struct OriginalStartFailureContent: View {
    @Environment(\.linYuColors) private var colors
    let message: String
    let bills: [CampusUnpaidBill]
    var busy = false
    let onDeduct: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 24) {
                Text(bills.isEmpty ? "开阀失败" : "开阀失败 · 有未扣账单").font(LinYuType.font(24, weight: .bold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(message).font(LinYuType.font(14)).foregroundStyle(colors.textPrimary)
                        if !bills.isEmpty {
                            Text("检测到 \(bills.count) 笔没扣成功的账单：").font(LinYuType.font(13, weight: .medium)).foregroundStyle(colors.warning).padding(.top, 12).padding(.bottom, 6)
                            ForEach(bills) { bill in
                                Text("· ¥\(bill.consumeMoney ?? "?")   \(String((bill.consumeDate ?? "").prefix(16)))")
                                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                            }
                            Text("账户有欠费时服务端会拒绝开阀").font(LinYuType.font(11)).foregroundStyle(colors.textSecondary).padding(.top, 8)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true).frame(maxHeight: 320)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("关闭", action: onDismiss).buttonStyle(.plain).foregroundStyle(colors.accent).padding(.horizontal, 12)
                    if bills.isEmpty {
                        Button("知道了", action: onDismiss).buttonStyle(.plain).foregroundStyle(colors.accent).padding(.horizontal, 12)
                    } else {
                        Button("立即补扣", action: onDeduct).buttonStyle(LinYuButtonStyle(color: colors.warning)).disabled(busy)
                    }
                }
            }
        }.accessibilityIdentifier("linyu.device.start-failure")
    }
}

/// Shared by home and wallet: an unknown amount never authorizes a deduction.
struct OriginalDeductConfirmDialog: View {
    @Environment(\.linYuColors) private var colors
    let amount: Double?
    let detail: String
    var busy = false
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    private var known: Bool { amount?.isFinite == true }
    var body: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 24) {
                Text("确认扣款").font(LinYuType.font(24, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("将从校园卡中扣除：").font(LinYuType.font(13)).foregroundStyle(colors.textSecondary)
                    Text(known ? "¥" + OriginalFormatting.money(amount!) : "金额无法识别")
                        .font(LinYuType.font(22, weight: .bold)).foregroundStyle(known ? colors.danger : colors.textSecondary).padding(.top, 8)
                    Text(detail).font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.top, 6)
                    Text(known ? "余额不足时会扣款失败" : "服务端返回的金额格式不对，无法确认将扣多少钱。请到「钱包」页逐笔核对后再操作。")
                        .font(LinYuType.font(11)).foregroundStyle(known ? colors.textSecondary : colors.warning).padding(.top, 12)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("取消", action: onDismiss).buttonStyle(.plain).foregroundStyle(colors.accent).padding(.horizontal, 12).disabled(busy)
                    Button("确认扣款") { guard known, !busy else { return }; onConfirm() }
                        .buttonStyle(LinYuButtonStyle(color: colors.warning)).disabled(!known || busy)
                        .accessibilityIdentifier("linyu.deduct.confirm")
                }
            }
        }.accessibilityIdentifier(known ? "linyu.deduct.known" : "linyu.deduct.unknown")
    }
}

struct OriginalStartingDeviceDialog: View {
    @Environment(\.linYuColors) private var colors
    var progress: String? = nil
    var body: some View {
        LinYuDialogCard {
            VStack(spacing: 24) {
                Text("正在开启热水器...").font(LinYuType.font(24, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    ProgressView().tint(colors.accent).frame(width: 24, height: 24)
                    Text(progress ?? "正在确认设备是否开启，请稍候").foregroundStyle(colors.textSecondary)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

struct OriginalBluetoothRetryDialog: View {
    @Environment(\.linYuColors) private var colors
    let device: CampusDevice
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        LinYuDialogCard {
            VStack(spacing: 24) {
                Text("要用蓝牙方式开启吗？").font(LinYuType.font(24, weight: .bold)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Text("「\(device.displayName)」无法通过云端开启。\n\n如果这台设备需要手机蓝牙直连（开启时必须待在设备旁边），可以改用蓝牙方式。\n\n不确定的话：用官方「趣智校园」试一下——需要站到设备旁才能开的就是这一类。")
                    .font(LinYuType.font(14)).lineSpacing(6).foregroundStyle(colors.textSecondary)
                VStack(spacing: 8) {
                    Button("用蓝牙开启", action: onConfirm).frame(maxWidth: .infinity).buttonStyle(LinYuButtonStyle())
                    Button("取消", action: onDismiss).buttonStyle(.plain).foregroundStyle(colors.accent).frame(height: 40)
                }
            }
        }
    }
}

struct OriginalAutomaticCloseDialog: View {
    @Environment(\.linYuColors) private var colors
    let event: OriginalFinishNotice
    var amount: Double? = nil
    var loading = false
    let onConfirm: () -> Void
    private var elapsed: String { let seconds = max(0, event.duration); return seconds >= 60 ? "\(seconds / 60)分\(seconds % 60)秒" : "\(seconds)秒" }
    var body: some View {
        LinYuDialogCard {
            VStack(spacing: 24) {
                Text("⚠️ 热水器已自动关闭").font(LinYuType.font(24, weight: .bold)).multilineTextAlignment(.center)
                VStack(spacing: 0) {
                    HStack(spacing: 0) { Text("🚿 ").font(LinYuType.font(16)); Text(event.title).font(LinYuType.font(14, weight: .medium)) }
                    Text("⏱ 已用 " + elapsed).foregroundStyle(colors.textSecondary).padding(.top, 6)
                    if loading {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini).tint(colors.accent); Text("结算中...").foregroundStyle(colors.textSecondary) }.padding(.top, 12)
                    } else {
                        Text(amount.flatMap { $0.isFinite ? "本次消费：¥" + OriginalFormatting.money($0) : nil } ?? "消费金额稍后可在账单中查看")
                            .font(LinYuType.font(14, weight: .bold)).foregroundStyle(colors.accent).padding(.top, 12)
                    }
                }.frame(maxWidth: .infinity)
                Button(action: onConfirm) { Text("确 认").frame(maxWidth: .infinity) }.buttonStyle(LinYuButtonStyle())
            }
        }
    }
}
