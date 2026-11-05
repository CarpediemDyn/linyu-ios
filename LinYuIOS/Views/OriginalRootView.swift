import SwiftUI
import Charts

@MainActor struct OriginalRootView: View {
    @StateObject private var model = OriginalAppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var scanner = false
    @Namespace private var capsule
    var body: some View {
        ZStack(alignment: .bottom) {
            OriginalBackground(preferences: model.preferences, shower: false)
            if model.auth.session == nil {
                AccountView(auth: model.auth).scrollContentBackground(.hidden)
            } else {
                VStack(spacing: 0) {
                    Group {
                        switch page {
                        case 1: OriginalWalletView(model: model)
                        case 2: OriginalProfileView(model: model)
                        default: home
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 5) {
                        tab("首页", "house.fill", 0)
                        tab("钱包", "wallet.pass.fill", 1)
                        tab("我的", "person.fill", 2)
                    }.padding(6).background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.4))).padding(.horizontal, 55).padding(.bottom, 10)
                }
            }
            if !model.message.isEmpty {
                Text(model.message).font(.subheadline).padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 24).padding(.bottom, 85).transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task(id: model.message) {
                        let text = model.message
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if model.message == text { model.message = "" }
                    }
            }
        }
        .tint(model.preferences.accentColor)
        .preferredColorScheme(model.preferences.theme == "dark" ? .dark : model.preferences.theme == "light" ? .light : nil)
        .sheet(isPresented: $scanner) { OriginalScannerView { code in Task { await model.scanCode(code) } } }
        .sheet(item: $model.selectedDevice) { device in OriginalDeviceDetail(model: model, device: device).presentationDetents([.medium, .large]) }
        .sheet(item: $model.startFailure) { failure in OriginalStartFailureView(model: model, failure: failure) }
        .fullScreenCover(isPresented: Binding(get: { model.showShower != nil || model.showCloudShower != nil }, set: { if !$0 { model.showShower = nil; model.showCloudShower = nil } })) {
            OriginalShowerView(model: model)
        }
        .onAppear { model.setForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { model.setForeground($0 == .active) }
        .onOpenURL { url in Task { await model.handle(url) } }
        .confirmationDialog("该设备离线或需要手机蓝牙直连", isPresented: Binding(get: { model.pendingBluetoothFallback != nil }, set: { if !$0 { model.pendingBluetoothFallback = nil } }), titleVisibility: .visible) {
            if let device = model.pendingBluetoothFallback {
                Button("使用蓝牙直连重试") { model.pendingBluetoothFallback = nil; model.setBluetooth(true, device: device); Task { await model.start(device) } }
            }
            Button("取消", role: .cancel) { model.pendingBluetoothFallback = nil }
        }
        .alert(item: $model.automaticFinish) { event in
            Alert(title: Text("热水器已自动关闭"), message: Text("\(event.title)\n使用时长：\(max(0, event.duration) / 60)分\(max(0, event.duration) % 60)秒\n消费金额稍后可在账单中查看"), dismissButton: .default(Text("知道了")))
        }
    }
    private func tab(_ title: String, _ symbol: String, _ index: Int) -> some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { page = index } } label: {
            VStack(spacing: 3) { Image(systemName: symbol); Text(title).font(.caption2) }
                .foregroundStyle(page == index ? model.preferences.accentColor : Color.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background { if page == index { Capsule().fill(model.preferences.accentColor.opacity(0.12)).matchedGeometryEffect(id: "tab", in: capsule) } }
        }.buttonStyle(.plain)
    }
    private var home: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Image("OriginalLogo").resizable().scaledToFit().frame(width: 36, height: 36); Text("淋浴").font(.largeTitle.bold()) }
                            Text(model.account?.profile.schoolName ?? "趣智校园").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { scanner = true } label: { Image(systemName: "qrcode.viewfinder").font(.title2).padding(12).background(.ultraThinMaterial, in: Circle()) }
                    }
                    OriginalGlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(model.balance?.title ?? "余额").foregroundStyle(.secondary)
                                Text(model.balance?.formattedBalance ?? "¥ —").font(.system(size: 34, weight: .bold, design: .rounded))
                                if model.balance?.isEstimated == true { Text("本地估算，并非真实余额").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(); Image(systemName: "drop.fill").font(.system(size: 40)).foregroundStyle(model.preferences.accentColor.opacity(0.6))
                        }
                    }
                    if !model.activeBluetooth.isEmpty || !model.currentCloud.isEmpty {
                        Text("使用中").font(.headline)
                        ForEach(model.activeBluetooth) { record in
                            OriginalGlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(OriginalFormatting.deviceName(record.binding.device.name)).font(.headline)
                                    Text(record.statusText).font(.subheadline).foregroundStyle(.secondary)
                                    HStack {
                                        Text(record.startedAt ?? record.updatedAt, style: .timer).monospacedDigit()
                                        Spacer()
                                        Button(record.valve == .closed ? "继续结算" : "结束使用") { Task { await model.endBluetooth(record) } }.disabled(model.isBusy)
                                    }
                                }.contentShape(Rectangle()).onTapGesture { model.showShower = record.id }
                            }
                        }
                        ForEach(model.currentCloud) { order in
                            OriginalGlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(OriginalFormatting.deviceName(order.deviceName)).font(.headline)
                                    HStack { Text(order.startedAt, style: .timer).monospacedDigit(); Spacer(); Button("结束使用") { Task { await model.endCloud(order.snCode) } }.disabled(model.isBusy) }
                                }.contentShape(Rectangle()).onTapGesture { model.showCloudShower = order.snCode }
                            }
                        }
                    }
                    if let last = model.account?.lastDevice {
                        Text("上次使用").font(.headline)
                        OriginalGlassCard {
                            HStack { Text(last.emoji).font(.title); VStack(alignment: .leading) { Text(last.displayName).font(.headline); Text(last.typeLabel).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("快速开始") { Task { await model.start(last) } }.disabled(model.isBusy) }
                        }
                    }
                    HStack {
                        Text("附近设备").font(.headline); Spacer()
                        if model.ble.scanning { ProgressView() }
                        Button(model.ble.scanning ? "停止" : "扫描") { if model.ble.scanning { model.ble.stopScan() } else { model.ble.startScan() } }.disabled(model.isBusy)
                    }
                    if !(model.account?.boundRoom ?? "").isEmpty { Label(model.account?.boundRoom ?? "", systemImage: "building.2").font(.caption).foregroundStyle(.secondary) }
                    if model.filteredMeters.isEmpty {
                        OriginalGlassCard { VStack(spacing: 12) { Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(model.preferences.accentColor); Text("靠近水表后扫描附近设备"); Text(model.ble.bluetoothStatus).font(.caption).foregroundStyle(.secondary); Button("开始扫描") { model.ble.startScan() }.disabled(model.isBusy) }.frame(maxWidth: .infinity).padding() }
                    }
                    ForEach(model.filteredMeters) { meter in
                        Button { Task { await model.choose(meter) } } label: {
                            OriginalGlassCard {
                                HStack(spacing: 14) {
                                    Text(model.nearby[meter.id]?.emoji ?? "🚿").font(.title)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(model.nearby[meter.id]?.displayName ?? meter.name).font(.headline).foregroundStyle(.primary)
                                        Text("信号：\(meter.rssi > -65 ? "强" : meter.rssi > -80 ? "中" : "弱")").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain).disabled(model.isBusy)
                    }
                    if model.isBusy { ProgressView("正在处理…").frame(maxWidth: .infinity) }
                }.padding(20).padding(.bottom, 12)
            }.refreshable { await model.refresh() }.toolbar(.hidden, for: .navigationBar).background(Color.clear)
        }.scrollContentBackground(.hidden)
    }
}

@MainActor extension OriginalPreferences {
    func viewBinding<Value>(_ keyPath: ReferenceWritableKeyPath<OriginalPreferences, Value>) -> Binding<Value> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

struct OriginalGlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.28), lineWidth: 0.8))
    }
}

@MainActor struct OriginalBackground: View {
    @ObservedObject var preferences: OriginalPreferences
    let shower: Bool
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            let path = shower ? preferences.showerBackground : preferences.homeBackground
            if let image = OriginalBackgroundPalette.background(path: path, asset: shower ? "OriginalShower" : "OriginalHome", brightness: preferences.backgroundBrightness(shower: shower)) {
                Image(uiImage: image).resizable().scaledToFill().opacity(preferences.backgroundOpacity(shower: shower)).blur(radius: preferences.backgroundBlur(shower: shower))
            }
        }.ignoresSafeArea().clipped()
    }
}

@MainActor private struct OriginalDeviceDetail: View {
    @ObservedObject var model: OriginalAppModel
    let device: CampusDevice
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(device.emoji).font(.system(size: 50)).frame(maxWidth: .infinity); Text(device.displayName).font(.title3.bold()); LabeledContent("类型", value: device.typeLabel); LabeledContent("预扣金额", value: "¥ \(OriginalFormatting.money(device.withholdMoney ?? 0))"); LabeledContent("设备编号", value: device.snCode) }
                Section {
                    Toggle("蓝牙直连设备", isOn: Binding(get: { model.usesBluetooth(device) }, set: { model.setBluetooth($0, device: device) }))
                    Text("需靠近设备开启手机蓝牙的水表使用蓝牙直连；联网设备沿用原版云端通道。").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    if let active = model.activeBluetooth.first(where: { $0.binding.device.deviceId == device.deviceId }) {
                        Button("结束使用") { dismiss(); Task { await model.endBluetooth(active) } }
                    } else if model.cloud.active.contains(where: { $0.snCode == device.snCode }) {
                        Button("结束使用") { dismiss(); Task { await model.endCloud(device.snCode) } }
                    } else {
                        Button("开始使用") { dismiss(); Task { await model.start(device) } }
                    }
                }.disabled(model.isBusy)
            }.navigationTitle("设备详情").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

@MainActor private struct OriginalStartFailureView: View {
    @ObservedObject var model: OriginalAppModel
    let failure: OriginalStartFailure
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    private var bills: [CampusUnpaidBill] { failure.bills(in: model.unpaid) }
    var body: some View {
        NavigationStack {
            List {
                Section { Text(failure.message) }
                if !bills.isEmpty {
                    Section("检测到 \(bills.count) 笔未扣账单") {
                        ForEach(bills) { bill in
                            Text("¥ \(bill.consumeMoney ?? "?")   \(String((bill.consumeDate ?? "").prefix(16)))")
                        }
                        Text("账户有欠费时服务端会拒绝开阀").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("立即补扣") { confirming = true }.disabled(model.isBusy)
                }
            }
            .navigationTitle(bills.isEmpty ? "开阀失败" : "开阀失败 · 有未扣账单")
            .toolbar { Button("关闭") { dismiss() } }
            .alert("确认补扣", isPresented: $confirming) {
                Button("取消", role: .cancel) {}
                Button("确认扣款") { model.startFailure = nil; Task { await model.deductAll() } }
            } message: {
                if let total = failure.total(for: bills) {
                    Text("共 \(bills.count) 笔，合计 ¥ \(OriginalFormatting.money(total))。将向服务端请求扣款，请确认后继续。")
                } else {
                    Text("共 \(bills.count) 笔，金额无法确认。将按服务端账单实际金额请求扣款，请确认后继续。")
                }
            }
        }.presentationDetents([.medium, .large])
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
