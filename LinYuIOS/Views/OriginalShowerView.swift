import SwiftUI

@MainActor struct OriginalShowerView: View {
    @ObservedObject var model: OriginalAppModel
    let onBack: () -> Void
    @Environment(\.linYuColors) private var colors
    @State private var stopping = false
    @State private var stopConfirmation: StopTarget?

    private enum StopTarget: Equatable {
        case bluetooth(UUID)
        case cloud(serial: String, orderNumber: String)
    }

    private var record: WaterTransaction? { model.bluetoothTransactions.first { $0.id == model.showShower } }
    private var order: CloudActiveOrder? { model.currentCloud.first { $0.snCode == model.showCloudShower } }
    private var settling: Bool { model.settlingBluetooth.map { $0 == model.showShower } ?? false }
    private var closeUnconfirmed: Bool { model.unconfirmedBluetoothClose.map { $0 == model.showShower } ?? false }
    private var hasCustomBackground: Bool { !model.preferences.showerBackground.isEmpty }

    private var device: CampusDevice? {
        guard let serial = record?.binding.device.snCode ?? order?.snCode else { return nil }
        let knownDevices = [model.account?.lastDevice, model.selectedDevice].compactMap { $0 }
        if let known = knownDevices.first(where: { $0.snCode == serial }) { return known }
        if let nearby = model.nearby.values.first(where: { $0.snCode == serial }) { return nearby }
        if let ledger = record?.binding.device {
            return CampusDevice(deviceName: ledger.name, snCode: serial, bigTypeId: ledger.bigTypeId)
        }
        if let order { return CampusDevice(deviceName: order.deviceName, snCode: serial) }
        return nil
    }

    private var stopDisabled: Bool { stopping || model.isBusy }
    private var stopTarget: StopTarget? {
        if let record { return .bluetooth(record.id) }
        if let order { return .cloud(serial: order.snCode, orderNumber: order.orderNo) }
        return nil
    }
    private var confirmingStop: Binding<Bool> {
        Binding(get: { stopConfirmation != nil }, set: { if !$0 { stopConfirmation = nil } })
    }

    var body: some View {
        Group {
            if record?.usageState == .running || order != nil {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    showerContent(at: timeline.date)
                }
            } else {
                showerContent(at: .now)
            }
        }
        .background {
            if hasCustomBackground {
                OriginalBackground(preferences: model.preferences, shower: true)
            }
        }
        .linYuModal(isPresented: confirmingStop) { endUseDialog }
        .onAppear { model.showerAppeared() }
        .interactiveDismissDisabled(stopping)
        .accessibilityAction(.escape) {
            if stopConfirmation != nil { stopConfirmation = nil } else { onBack() }
        }
    }

    private func showerContent(at date: Date) -> some View {
        let device = self.device
        let elapsed = record?.usageSeconds(at: date)
            ?? order.map { max(0, Int(date.timeIntervalSince($0.startedAt))) }
        let countdown = order?.autoDisconnectAt.map { max(0, Int(ceil($0.timeIntervalSince(date)))) } ?? 0
        let needsRecovery = record.map { $0.usageState != .running } ?? false
        let isSettlementRecovery = record?.isSettlementRecovery == true
        let needsNearbyMeter = isSettlementRecovery
            && record.map { !model.ble.isAvailableForRecovery($0.binding.peripheralID) } == true
        let recoveryNote = settling ? model.bluetoothSettlementProgress : record?.lastError
        let showMeterGuidance = needsNearbyMeter && recoveryNote?.contains(WaterError.meterRecoveryGuidance) != true
        return OriginalShowerContent(
            emoji: device?.emoji ?? "🚿",
            status: needsRecovery ? (record?.statusText ?? "") : (device?.statusText ?? "正在沐浴中"),
            location: device?.displayName ?? "",
            preDeduct: device?.withholdMoney,
            elapsed: elapsed,
            countdown: countdown,
            hasCustomBackground: hasCustomBackground,
            stopping: stopping && !closeUnconfirmed,
            settling: settling,
            stopDisabled: stopDisabled,
            continuingSettlement: isSettlementRecovery,
            recoveryNote: recoveryNote,
            meterGuidance: showMeterGuidance ? WaterError.meterRecoveryGuidance : nil,
            meterScan: needsNearbyMeter && !settling ? { model.ble.startScan() } : nil,
            scanningForMeter: model.ble.scanning,
            onBack: onBack,
            onStop: requestStop
        )
    }

    private var endUseDialog: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("确认结束使用").font(LinYuType.font(24, weight: .bold))
                Text("确认后将尝试关闭当前设备并结算本次用水。")
                    .font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("取消") { stopConfirmation = nil }
                        .buttonStyle(.plain).foregroundStyle(colors.accent).padding(.horizontal, 12)
                    Button("结束使用") {
                        guard stopTarget == stopConfirmation else { stopConfirmation = nil; return }
                        stopConfirmation = nil
                        stop()
                    }.buttonStyle(LinYuButtonStyle(color: Color(linYuHex: 0xE53935)))
                        .disabled(stopDisabled || stopTarget != stopConfirmation)
                }.padding(.top, 8)
            }
        }
    }

    private func requestStop() {
        guard !stopDisabled else { return }
        if record?.isSettlementRecovery == true || stopTarget == nil {
            stop()
        } else {
            stopConfirmation = stopTarget
        }
    }

    private func stop() {
        guard !stopDisabled else { return }
        if let record {
            stopping = true
            Task {
                defer { stopping = false }
                await model.endBluetooth(record)
            }
        } else if let order {
            stopping = true
            Task {
                defer { stopping = false }
                await model.endCloud(order.snCode)
            }
        } else {
            onBack()
        }
    }
}

struct OriginalShowerContent: View {
    let emoji: String
    let status: String
    let location: String
    let preDeduct: Double?
    let elapsed: Int?
    let countdown: Int
    let hasCustomBackground: Bool
    let stopping: Bool
    var settling = false
    let stopDisabled: Bool
    let continuingSettlement: Bool
    var recoveryNote: String? = nil
    var meterGuidance: String? = nil
    var meterScan: (() -> Void)? = nil
    var scanningForMeter = false
    let onBack: () -> Void
    let onStop: () -> Void
    @Environment(\.linYuColors) private var colors
    @ScaledMetric(relativeTo: .title2) private var statusSize: CGFloat = 22
    @ScaledMetric(relativeTo: .headline) private var actionSize: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if !hasCustomBackground {
                    let stops: [UInt32] = colors.isDark ? [0x1A237E, 0x283593, 0x3949AB] : [0xE3F2FD, 0xBBDEFB, 0x90CAF9]
                    LinearGradient(colors: stops.map { Color(linYuHex: $0) }, startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea().accessibilityHidden(true)
                }
                ScrollView {
                    details(compact: geometry.size.height < 460)
                        .padding(geometry.size.width < 360 ? 12 : 24)
                        .frame(maxWidth: 520).frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                }
                Button(action: onBack) {
                    LinYuIcon(name: "arrow_back").foregroundStyle(colors.textPrimary)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(8)
                .accessibilityLabel(continuingSettlement ? "返回首页" : "返回（不结束用水）")
                .accessibilityIdentifier("linyu.shower.back")
            }
        }
    }

    private func details(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if !hasCustomBackground {
                LinYuDeviceGlyph(emoji: emoji, size: compact ? 48 : 72).foregroundStyle(.white)
                    .padding(.bottom, 8)
            }
            Text(status).font(LinYuType.font(statusSize, weight: .bold)).foregroundStyle(colors.accent)
                .multilineTextAlignment(.center)
            Text(location).font(LinYuType.font(16)).foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center).padding(.top, 4)
            if let recoveryNote {
                Text(recoveryNote).font(LinYuType.font(14)).multilineTextAlignment(.center)
                    .foregroundStyle(colors.textSecondary).padding(.top, 8)
                    .accessibilityIdentifier("linyu.shower.recovery-status")
            }
            preDeductCard(preDeduct).padding(.top, compact ? 16 : 32)
            timerBadge(elapsed).padding(.top, compact ? 12 : 24)
            if countdown > 0 { countdownBadge(countdown).padding(.top, 12) }
            if let meterGuidance {
                Text(meterGuidance).font(LinYuType.font(14)).multilineTextAlignment(.center)
                    .foregroundStyle(colors.textSecondary).padding(.top, 12)
            }
            stopButton.padding(.top, compact ? 20 : 48)
            if continuingSettlement {
                if let meterScan {
                    Button(scanningForMeter ? "正在扫描原水表…" : "扫描附近水表", action: meterScan)
                        .buttonStyle(.plain).foregroundStyle(colors.accent)
                        .frame(minHeight: 44).disabled(stopDisabled || scanningForMeter)
                }
                Button("返回首页", action: onBack)
                    .buttonStyle(.plain).foregroundStyle(colors.accent).frame(minHeight: 44)
            }
            Text("费率: 0.041元/升 · 设备: \(String(location.suffix(6)))")
                .font(LinYuType.font(11)).foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center).padding(.top, 16)
        }.frame(maxWidth: .infinity)
    }

    private func preDeductCard(_ amount: Double?) -> some View {
        let formatted = amount.flatMap { $0.isFinite && $0 >= 0 ? OriginalFormatting.money($0) : nil } ?? "—"
        let shape = RoundedRectangle(cornerRadius: 16)
        return VStack(spacing: 4) {
            Text("💧 已预扣 ¥\(formatted)")
                .font(LinYuType.font(18, weight: .bold)).foregroundStyle(colors.accent)
            Text("计费以热水器显示为准").font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
        }.padding(20).frame(maxWidth: .infinity)
            .background(colors.card, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(colors.isDark ? 0.18 : 0.6), lineWidth: 1))
    }

    private func timerBadge(_ seconds: Int?) -> some View {
        HStack(spacing: 8) {
            Text("⏱").font(LinYuType.font(18))
            Text(seconds.map { "\(continuingSettlement ? "本次用水" : "已用") \(timeText($0))" }
                 ?? "上次用水时长待核实").font(LinYuType.font(16, weight: .medium))
                .foregroundStyle(colors.textPrimary).accessibilityIdentifier("linyu.shower.duration")
        }.padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(linYuHex: colors.isDark ? 0x1D232E : 0xFFFFFF, alpha: 0.6),
                        in: RoundedRectangle(cornerRadius: 12))
    }

    private func countdownBadge(_ seconds: Int) -> some View {
        HStack(spacing: 8) {
            Text("⏳").font(LinYuType.font(18))
            Text("闲置约 \(timeText(seconds)) 后自动关闭").font(LinYuType.font(13))
                .foregroundStyle(colors.warning)
        }.padding(.horizontal, 20).padding(.vertical, 10)
            .background(colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var stopButton: some View {
        Button(action: onStop) {
            HStack(spacing: 8) {
                if stopping || settling { OriginalWaterSpinner(size: 20, color: .white) }
                Text(settling ? "正在核实结算…" : stopping ? "正在关闭…" : continuingSettlement ? "继续核实结算" : "结 束 使 用")
                    .font(LinYuType.font(actionSize, weight: .bold)).tracking(2)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity).frame(minHeight: 56)
                .background(Color(linYuHex: 0xE53935, alpha: stopDisabled ? 0.4 : 1), in: Capsule())
                .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
        }.buttonStyle(.plain).disabled(stopDisabled)
            .accessibilityIdentifier("linyu.shower.stop")
    }

    private func timeText(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)分\(seconds % 60)秒" : "\(seconds)秒"
    }
}
