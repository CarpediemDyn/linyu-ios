import SwiftUI
import Charts

@MainActor struct OriginalRootView: View {
    @StateObject private var model = OriginalAppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var direction = 1
    @State private var scanner = false
    @State private var inSettings = false
    @State private var opening = false
    @State private var sessionNotice = false
    private enum Dialog { case session, automatic, opening, retry, failure, device }
    private var dialog: Dialog? {
        if sessionNotice { return .session }
        if model.automaticFinish != nil { return .automatic }
        if opening { return .opening }
        if model.pendingBluetoothFallback != nil { return .retry }
        if model.startFailure != nil { return .failure }
        if model.selectedDevice != nil { return .device }
        return nil
    }
    private var canDismissDialog: Bool { dialog != .session && dialog != .opening && dialog != .automatic && !model.isBusy }
    private var tab: Binding<Int> {
        Binding(get: { page }, set: { next in
            direction = next > page ? 1 : -1
            inSettings = false
            page = next
        })
    }
    var body: some View {
        LinYuThemeHost(preferences: model.preferences) {
            ZStack(alignment: .bottom) {
                OriginalBackground(preferences: model.preferences, shower: false)
                if model.auth.session == nil {
                    AccountView(auth: model.auth)
                } else {
                    pages
                    if !inSettings { LinYuPillNavigation(selection: tab).padding(.bottom, 22) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                OriginalToast(message: model.message) { text in
                    if model.message == text { model.message = "" }
                }
            }
            .linYuModal(isPresented: Binding(get: { dialog != nil }, set: { visible in if !visible { dismissDialog() } }),
                        canDismiss: canDismissDialog) { dialogContent }
            .fullScreenCover(isPresented: $scanner) {
                OriginalScannerView { code in Task { await model.scanCode(code) } }
            }
            .fullScreenCover(isPresented: Binding(get: { model.showShower != nil || model.showCloudShower != nil },
                                                  set: { if !$0 { closeShowerPage() } })) {
                OriginalShowerView(model: model)
            }
        }
        .onAppear { model.setForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { model.setForeground($0 == .active) }
        .onChange(of: model.auth.session?.ownerScope) { owner in
            if owner != nil { page = 0; inSettings = false; sessionNotice = false }
            else if model.auth.activity.contains("登录状态已失效") { sessionNotice = true }
        }
        .onOpenURL { url in Task { await model.handle(url) } }
    }
    private var pages: some View {
        Group {
            switch page {
            case 1: OriginalWalletView(model: model)
            case 2: OriginalProfileView(model: model)
            default: OriginalHomeView(model: model, onScan: { scanner = true }, onStart: start)
            }
        }
        .id(page).frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)))
        .animation(.interpolatingSpring(stiffness: 420, damping: 32), value: page)
        .clipped()
    }
    @ViewBuilder private var dialogContent: some View {
        switch dialog {
        case .session:
            LinYuDialogCard {
                VStack(spacing: 24) {
                    Text("登录状态已失效").font(LinYuType.font(24, weight: .bold))
                    Text("当前登录已失效。设备可能仍在用水，请重新登录核对，或立即使用官方客户端、联系人工处理。")
                        .multilineTextAlignment(.center)
                    Button { sessionNotice = false } label: { Text("确定").frame(maxWidth: .infinity) }.buttonStyle(LinYuButtonStyle())
                }.frame(maxWidth: .infinity)
            }
        case .automatic:
            if let event = model.automaticFinish {
                OriginalAutomaticCloseDialog(event: event) { model.automaticFinish = nil }
            }
        case .opening: OriginalStartingDeviceDialog()
        case .retry:
            if let device = model.pendingBluetoothFallback {
                OriginalBluetoothRetryDialog(device: device, onConfirm: {
                    guard !model.isBusy else { return }
                    model.pendingBluetoothFallback = nil
                    model.setBluetooth(true, device: device)
                    start(device)
                }, onDismiss: { model.pendingBluetoothFallback = nil })
            }
        case .failure:
            if let failure = model.startFailure {
                OriginalStartFailureView(model: model, failure: failure) { model.startFailure = nil }
            }
        case .device:
            if let device = model.selectedDevice {
                OriginalDeviceDetail(model: model, device: device, onStart: start) { model.selectedDevice = nil }
            }
        case nil: EmptyView()
        }
    }
    private func dismissDialog() {
        guard canDismissDialog else { return }
        switch dialog {
        case .retry: model.pendingBluetoothFallback = nil
        case .failure: model.startFailure = nil
        case .device: model.selectedDevice = nil
        default: break
        }
    }
    private func closeShowerPage() { model.showShower = nil; model.showCloudShower = nil }
    private func start(_ device: CampusDevice) {
        guard !opening, !model.isBusy else { return }
        opening = true
        Task { await model.start(device); opening = false }
    }
}

struct OriginalToast: View {
    let message: String
    let onFinish: (String) -> Void
    @State private var visible = false
    var body: some View {
        Group {
            if visible && !message.isEmpty {
                HStack(spacing: 12) {
                    Image("OriginalLogo").resizable().frame(width: 32, height: 32)
                    LinYuTailText(text: message, size: 14, weight: .medium).foregroundStyle(.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color(linYuHex: 0x1F2937), in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                .padding(.horizontal, 24).padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }.allowsHitTesting(false)
            .task(id: message) {
                let text = message
                withAnimation(.easeOut(duration: 0.25)) { visible = !text.isEmpty }
                guard !text.isEmpty else { return }
                do {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeIn(duration: 0.3)) { visible = false }
                    try await Task.sleep(nanoseconds: 300_000_000)
                    onFinish(text)
                } catch {}
            }
    }
}



@MainActor private struct OriginalShowerView: View {
    @ObservedObject var model: OriginalAppModel
    @Environment(\.dismiss) private var dismiss
    private var record: WaterTransaction? { model.activeBluetooth.first { $0.id == model.showShower } }
    private var order: CloudActiveOrder? { model.cloud.active.first { $0.snCode == model.showCloudShower } }
    var body: some View {
        ZStack {
            OriginalBackground(preferences: model.preferences, shower: true)
            VStack(spacing: 28) {
                HStack { Button("收起") { dismiss() }; Spacer(); Text("淋浴").font(.headline); Spacer() }.padding()
                Spacer()
                Image(systemName: "drop.fill").font(.system(size: 72)).foregroundStyle(model.preferences.accentColor)
                Text("正在用水").font(.title2.bold())
                Text(record?.startedAt ?? order?.startedAt ?? record?.updatedAt ?? Date(), style: .timer).font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                Text(OriginalFormatting.deviceName(record?.binding.device.name ?? order?.deviceName ?? "用水已结束")).font(.headline)
                if let order, order.autoDisconnectAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text("闲置自动关闭倒计时：\(order.autoDisconRemain) 秒").font(.subheadline).foregroundStyle(.secondary) }
                }
                if let record { Text(record.statusText).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    if let record { Task { await model.endBluetooth(record) } }
                    else if let order { Task { await model.endCloud(order.snCode) } }
                    else { dismiss() }
                } label: { Text(model.isBusy ? "正在结束…" : "结束使用").font(.headline).frame(maxWidth: .infinity).padding(20).background(model.preferences.accentColor, in: Capsule()).foregroundStyle(.white) }
                    .disabled(model.isBusy).padding(30)
            }
        }.interactiveDismissDisabled(model.isBusy)
    }
}

@MainActor struct OriginalWalletView: View {
    @ObservedObject var model: OriginalAppModel
    @State private var editingBalance = false
    @State private var selectedBill: CampusBill?
    @State private var confirmingDebt: CampusUnpaidBill?
    @State private var confirmingAll = false
    private var deductible: [CampusUnpaidBill] { model.unpaid.filter(\.isDeductible) }
    private func deductionText(_ bills: [CampusUnpaidBill]) -> String {
        let total = OriginalStartFailure(message: "", serverRejected: true).total(for: bills)
        let amount = total.map { "合计 ¥ \(OriginalFormatting.money($0))" } ?? "金额无法确认，将按服务端账单实际金额扣款"
        return "共 \(bills.count) 笔，\(amount)。确认后向服务端请求扣款。"
    }
    private var trend: [OriginalDailySpend] {
        let calendar = Calendar.current
        let start = model.preferences.trendRange == "LAST_7_DAYS"
            ? calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!
            : calendar.dateInterval(of: .month, for: Date())!.start
        var daily: [Date: Double] = [:]
        for bill in model.bills {
            if let date = bill.date, date >= start, date <= Date() { daily[calendar.startOfDay(for: date), default: 0] += bill.amount }
        }
        var result: [OriginalDailySpend] = []
        var date = start
        let end = calendar.startOfDay(for: Date())
        while date <= end {
            result.append(OriginalDailySpend(date: date, amount: daily[date, default: 0]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("钱包").font(.largeTitle.bold())
                    OriginalGlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(model.balance?.title ?? "余额"); Spacer(); if model.balance?.isEstimated == true { Button("手动填写") { editingBalance = true }.font(.caption) } }
                            Text(model.balance?.formattedBalance ?? "¥ —").font(.system(size: 38, weight: .bold, design: .rounded))
                            Text(model.balance?.isEstimated == true ? "仅根据初始余额和账单估算，并非真实余额" : "来自账户的实时余额").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.preferences.trendEnabled {
                        OriginalGlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("消费趋势").font(.headline)
                                Picker("范围", selection: model.preferences.viewBinding(\.trendRange)) { Text("近7天").tag("LAST_7_DAYS"); Text("本月").tag("THIS_MONTH") }.pickerStyle(.segmented)
                                if trend.isEmpty { Text("暂无消费数据").foregroundStyle(.secondary) }
                                else {
                                    Chart(trend) { bill in
                                        if model.preferences.trendType == "BAR" { BarMark(x: .value("日期", bill.date, unit: .day), y: .value("金额", bill.amount)).foregroundStyle(model.preferences.accentColor.gradient) }
                                        else { LineMark(x: .value("日期", bill.date, unit: .day), y: .value("金额", bill.amount)).foregroundStyle(model.preferences.accentColor).interpolationMethod(.catmullRom) }
                                    }.frame(height: 150)
                                    Text("合计 ¥\(OriginalFormatting.money(trend.reduce(0) { $0 + $1.amount }))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !model.unpaid.isEmpty {
                        HStack { Text("未扣账单").font(.headline); Spacer(); Button("全部补扣") { confirmingAll = true }.disabled(model.isBusy || deductible.isEmpty) }
                        ForEach(model.unpaid) { bill in
                            OriginalGlassCard { HStack { VStack(alignment: .leading, spacing: 5) { Text(bill.description ?? "未扣账单"); Text("¥ \(bill.consumeMoney ?? "?")").bold() }; Spacer(); Button("请求代扣") { confirmingDebt = bill }.disabled(!bill.isDeductible || model.isBusy) } }
                        }
                    }
                    Text("账单").font(.headline)
                    if model.bills.isEmpty { Text("暂无账单数据").foregroundStyle(.secondary) }
                    ForEach(Array(model.bills.prefix(20))) { bill in
                        Button { selectedBill = bill; Task { await model.loadDetail(bill) } } label: {
                            OriginalGlassCard { HStack { Text(bill.emoji).font(.title); VStack(alignment: .leading, spacing: 5) { Text(bill.displayDesc).foregroundStyle(.primary); Text(bill.consumeDate).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("−¥\(OriginalFormatting.money(bill.amount))").bold().foregroundStyle(.primary) } }
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.refreshable { await model.refresh() }.toolbar(.hidden, for: .navigationBar)
            .alert("手动填写余额", isPresented: $editingBalance) { TextField("当前余额", text: $model.manualBalance).keyboardType(.decimalPad); Button("保存") { model.setManualBalance() }; Button("取消", role: .cancel) {} } message: { Text("仅用于本地估算，不会修改账户真实余额") }
            .confirmationDialog("确认请求代扣这笔未支付账单？", isPresented: Binding(get: { confirmingDebt != nil }, set: { if !$0 { confirmingDebt = nil } }), titleVisibility: .visible) {
                if let bill = confirmingDebt { Button("确认代扣") { confirmingDebt = nil; Task { await model.deduct(bill) } } }
                Button("取消", role: .cancel) { confirmingDebt = nil }
            } message: { Text(deductionText(confirmingDebt.map { [$0] } ?? [])) }
            .confirmationDialog("确认补扣全部 \(deductible.count) 笔未支付账单？", isPresented: $confirmingAll, titleVisibility: .visible) {
                Button("确认全部补扣") { Task { await model.deductAll() } }
                Button("取消", role: .cancel) {}
            } message: { Text(deductionText(deductible)) }
            .sheet(item: $selectedBill) { bill in
                NavigationStack { List { LabeledContent("设备", value: model.billDetail?.description ?? bill.displayDesc); LabeledContent("类型", value: bill.typeLabel); LabeledContent("消费金额", value: "¥ \(OriginalFormatting.money(model.billDetail?.consumeMoney ?? bill.amount))"); LabeledContent("消费时间", value: bill.consumeDate); LabeledContent("订单号", value: model.billDetail?.orderNo ?? bill.orderNo ?? bill.orderId) }.navigationTitle("账单详情").toolbar { Button("关闭") { selectedBill = nil } } }
            }
        }
    }
}

private struct OriginalDailySpend: Identifiable {
    let date: Date
    let amount: Double
    var id: Date { date }
}
