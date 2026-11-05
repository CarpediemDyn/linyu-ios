import SwiftUI
import CoreBluetooth
import UIKit

@MainActor struct OriginalHomeView: View {
    @ObservedObject var model: OriginalAppModel
    let onScan: () -> Void
    let onStart: (CampusDevice) -> Void
    @Environment(\.linYuColors) private var colors
    private var hasActive: Bool { !model.activeBluetooth.isEmpty || !model.currentCloud.isEmpty }
    private var needsPermission: Bool { CBCentralManager.authorization != .allowedAlways }
    private var balanceText: String {
        let title = model.balance?.title ?? "余额"
        guard let balance = model.balance else { return title + " ¥ —" }
        if balance.isEstimated && balance.manualBalance.isEmpty { return title + " ¥ —" }
        return title + " ¥" + OriginalFormatting.money(balance.balance)
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Color.clear.frame(height: 8)
                header
                activeSection
                HStack {
                    LinYuSectionTitle(title: "附近设备")
                    Spacer(minLength: 8)
                    Text(balanceText).font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
                }.padding(.top, 4)
                roomFilter
                if model.ble.scanning { scanningStatus }
                if needsPermission { permissionCard }
                else if model.filteredMeters.isEmpty && !model.ble.scanning {
                    Text((model.account?.boundRoom ?? "").isEmpty ? "未发现热水器" : "未找到寝室内的热水器")
                        .font(LinYuType.font(14)).foregroundStyle(colors.textSecondary).frame(maxWidth: .infinity).padding(32)
                }
                ForEach(model.filteredMeters) { meter in
                    let device = model.nearby[meter.id]
                    Button { Task { await model.choose(meter) } } label: {
                        OriginalNearbyDeviceRow(name: device?.displayName ?? OriginalFormatting.deviceName(meter.name),
                                                emoji: device?.emoji ?? "🚿", rssi: meter.rssi,
                                                address: device?.macAddress ?? meter.id.uuidString)
                    }.buttonStyle(LinYuPressStyle()).disabled(model.isBusy)
                }
                if model.isBusy {
                    HStack(spacing: 8) { ProgressView().tint(colors.accent); Text("正在确认设备信息，请稍候").font(LinYuType.font(13)).foregroundStyle(colors.textSecondary) }
                        .frame(maxWidth: .infinity)
                }
                Color.clear.frame(height: 110)
            }.padding(.horizontal, 20)
        }.refreshable { await refresh() }
            .onAppear { model.homeAppeared() }
            .task { if CBCentralManager.authorization == .allowedAlways { model.ble.startScan() } }
            .accessibilityIdentifier("linyu.home")
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("淋浴").font(LinYuType.font(30, weight: .bold)).foregroundStyle(colors.textPrimary)
                Text("Hualala").font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                LinYuIconButton(icon: "ic_qr_code_scanner", label: "扫描二维码", filled: true, action: onScan)
                LinYuIconButton(icon: "refresh", label: "刷新", filled: true) { Task { await refresh() } }
            }
        }
    }
    @ViewBuilder private var activeSection: some View {
        if hasActive {
            LinYuSectionTitle(title: "使用中的设备")
            ForEach(model.activeBluetooth) { record in
                OriginalSavedDeviceRow(name: OriginalFormatting.deviceName(record.binding.device.name),
                                       emoji: model.nearby.values.first(where: { $0.deviceId == record.binding.device.deviceId })?.emoji ?? model.account?.lastDevice.flatMap { $0.deviceId == record.binding.device.deviceId ? $0.emoji : nil } ?? "🚿",
                                       address: "", active: true) { model.showShower = record.id }
            }
            ForEach(model.currentCloud) { order in
                OriginalSavedDeviceRow(name: OriginalFormatting.deviceName(order.deviceName),
                                       emoji: model.nearby.values.first(where: { $0.snCode == order.snCode })?.emoji ?? model.account?.lastDevice.flatMap { $0.snCode == order.snCode ? $0.emoji : nil } ?? "🚿",
                                       address: order.deviceMac, active: true) { model.showCloudShower = order.snCode }
            }
        } else if let last = model.account?.lastDevice {
            LinYuSectionTitle(title: "上次使用设备")
            OriginalSavedDeviceRow(name: last.displayName, emoji: last.emoji, address: last.macAddress, active: false) {
                onStart(last)
            }.disabled(model.isBusy)
        }
    }
    @ViewBuilder private var roomFilter: some View {
        if let room = model.account?.boundRoom, !room.isEmpty {
            HStack(spacing: 8) {
                Text("🏠 已筛选：" + (OriginalFormatting.roomKey(room) ?? room))
                    .font(LinYuType.font(13, weight: .medium)).foregroundStyle(colors.accent)
                Button("取消筛选") { model.bindRoom(""); model.message = "已取消寝室筛选" }
                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).buttonStyle(.plain)
            }
        }
    }
    private var scanningStatus: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(colors.accent).frame(width: 14, height: 14)
                Text("扫描中...").font(LinYuType.font(13)).foregroundStyle(colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                OriginalSignalLegend(color: colors.success, title: "强")
                OriginalSignalLegend(color: colors.warning, title: "中")
                OriginalSignalLegend(color: colors.danger, title: "弱")
            }
        }
    }
    private var permissionCard: some View {
        OriginalGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("📶 开启扫描，发现附近设备").font(LinYuType.font(16, weight: .semibold)).foregroundStyle(colors.textPrimary)
                Text("需要允许蓝牙访问才能扫描附近的热水器。").font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.top, 6)
                Button {
                    if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } else { model.ble.startScan() }
                } label: { Text("授予权限并扫描").frame(maxWidth: .infinity) }
                    .buttonStyle(LinYuButtonStyle(cornerRadius: 12)).padding(.top, 12)
                Text("也可以直接用右上角 📷 扫码绑定设备，无需蓝牙权限")
                    .font(LinYuType.font(11)).foregroundStyle(colors.textSecondary).padding(.top, 6)
            }
        }
    }
    private func refresh() async { model.ble.startScan(); await model.refresh() }
}

private struct OriginalSignalLegend: View {
    @Environment(\.linYuColors) private var colors
    let color: Color
    let title: String
    var body: some View {
        HStack(spacing: 3) { Circle().fill(color).frame(width: 8, height: 8); Text(title).font(LinYuType.font(11)).foregroundStyle(colors.textSecondary) }
    }
}

/// Plain values and inert callbacks make these rows reusable in visual fixtures.
struct OriginalSavedDeviceRow: View {
    @Environment(\.linYuColors) private var colors
    let name: String
    let emoji: String
    let address: String
    let active: Bool
    let onUse: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            OriginalDeviceAvatar(emoji: emoji, active: active)
            VStack(alignment: .leading, spacing: 4) {
                LinYuTailText(text: name.isEmpty ? "热水器" : name).foregroundStyle(colors.textPrimary)
                if active {
                    HStack(spacing: 8) {
                        Text("使用中").font(LinYuType.font(11)).foregroundStyle(colors.warning).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(colors.activeBackground, in: RoundedRectangle(cornerRadius: 6))
                        Text("点击恢复订单").font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                    }
                } else {
                    LinYuTailText(text: "MAC: " + address, size: 12, weight: .regular).foregroundStyle(colors.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(active ? "恢复" : "开始", action: onUse).buttonStyle(LinYuButtonStyle())
        }.padding(16).frame(maxWidth: .infinity)
            .background(active ? colors.activeBackground : colors.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 0.8))
    }
}

struct OriginalNearbyDeviceRow: View {
    @Environment(\.linYuColors) private var colors
    let name: String
    let emoji: String
    let rssi: Int
    let address: String
    private var signalColor: Color { rssi >= -70 ? colors.success : rssi >= -85 ? colors.warning : colors.danger }
    var body: some View {
        OriginalGlassCard(padding: 16) {
            HStack(spacing: 14) {
                OriginalDeviceAvatar(emoji: emoji)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(LinYuType.font(16, weight: .semibold)).foregroundStyle(colors.textPrimary).multilineTextAlignment(.leading)
                    Text("信号强度: \(rssi) dBm").font(LinYuType.font(13)).foregroundStyle(signalColor).padding(.top, 6)
                    Text(address).font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.top, 2).lineLimit(1).truncationMode(.head)
                }.frame(maxWidth: .infinity, alignment: .leading)
                LinYuIcon(name: "keyboard_arrow_right").foregroundStyle(colors.textSecondary)
            }
        }
    }
}

private struct OriginalDeviceAvatar: View {
    @Environment(\.linYuColors) private var colors
    let emoji: String
    var active = false
    private var fill: Color {
        if emoji == "🪥" { return Color(linYuHex: 0xFFCC80) }
        if ["❄️", "♨️", "🚰"].contains(emoji) { return Color(linYuHex: 0x10B981) }
        return active ? colors.accent : Color(linYuHex: 0x2563EB)
    }
    var body: some View {
        Group {
            if emoji == "🚿" || emoji == "🪥" { LinYuDeviceGlyph(emoji: emoji, size: 26).foregroundStyle(.white) }
            else { Text(emoji).font(LinYuType.font(22)) }
        }.frame(width: 48, height: 48).background(fill, in: RoundedRectangle(cornerRadius: 14))
    }
}
