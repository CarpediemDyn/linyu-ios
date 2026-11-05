import SwiftUI

struct ProfileBoundRoomCard: View {
    @Environment(\.linYuColors) private var colors
    let room: String
    let onPick: () -> Void
    let onClear: () -> Void

    var body: some View {
        OriginalGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                ProfileCardTitle("绑定寝室")
                Group {
                    if room.isEmpty {
                        Text("未绑定寝室，设备列表将显示全部设备")
                            .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                    } else {
                        HStack(spacing: 8) {
                            Text("🏠 \(OriginalFormatting.roomKey(room) ?? room)")
                                .font(LinYuType.font(16, weight: .medium))
                                .foregroundStyle(colors.textPrimary).lineLimit(1).truncationMode(.tail)
                            ProfileTextAction("取消绑定", size: 12, color: colors.danger, action: onClear)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
                Button(action: onPick) { Text("选择附近").frame(maxWidth: .infinity) }
                    .buttonStyle(LinYuOutlinedButtonStyle(cornerRadius: 12)).padding(.top, 12)
            }
        }
    }
}

@MainActor struct ProfileRoomDialog: View {
    private struct Option: Identifiable {
        let id: String
        let meter: DiscoveredWaterMeter
        let isResolved: Bool
    }

    @ObservedObject var model: OriginalAppModel
    @Binding var locked: Bool
    let onClose: () -> Void
    @Environment(\.linYuColors) private var colors
    @State private var issue: String?

    private var options: [Option] {
        var seen = Set<String>()
        return model.ble.meters.compactMap { meter in
            let metadata = model.nearby[meter.id]
            guard let key = OriginalFormatting.roomKey(metadata?.deviceName ?? meter.name),
                  seen.insert(key).inserted else { return nil }
            return Option(id: key, meter: meter, isResolved: metadata != nil)
        }
    }

    var body: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 16) {
                ProfileDialogTitle("选择设备位置")
                let rooms = options
                if rooms.isEmpty {
                    Text("附近暂无设备").foregroundStyle(colors.textSecondary)
                } else {
                    let rowHeight: CGFloat = 48
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rooms) { room in
                                Button { choose(room) } label: {
                                    Text(room.id).font(LinYuType.font(14)).foregroundStyle(colors.textPrimary)
                                        .lineLimit(1).minimumScaleFactor(0.78).truncationMode(.head)
                                        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(locked || model.isBusy)
                            }
                        }
                    }
                    .frame(height: min(210, CGFloat(rooms.count) * rowHeight))
                }
                if locked || model.ble.scanning {
                    ProgressView().tint(colors.accent)
                }
                if let issue {
                    Text(issue).font(LinYuType.font(12)).foregroundStyle(colors.danger)
                }
                HStack(spacing: 0) {
                    Spacer()
                    if rooms.isEmpty && !model.ble.scanning {
                        ProfileTextAction("扫描") { model.ble.startScan() }.disabled(model.isBusy)
                    }
                    ProfileTextAction("关闭", action: onClose).disabled(locked)
                }
            }
        }
    }

    private func choose(_ room: Option) {
        guard !locked, !model.isBusy else { return }
        if room.isResolved {
            bind(room.id)
        } else {
            locked = true
            issue = nil
            Task {
                await model.choose(room.meter, showDetail: false)
                locked = false
                if let device = model.nearby[room.meter.id], let key = OriginalFormatting.roomKey(device.deviceName) {
                    bind(key)
                } else {
                    issue = "未能识别寝室，请靠近设备后重试"
                }
            }
        }
    }

    private func bind(_ key: String) {
        model.bindRoom(key)
        model.message = "已绑定寝室：\(key)"
        onClose()
    }
}
