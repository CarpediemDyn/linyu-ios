import SwiftUI

@MainActor struct OriginalWalletView: View {
    @ObservedObject var model: OriginalAppModel
    var onModalVisibilityChanged: (Bool) -> Void = { _ in }
    @Environment(\.linYuColors) private var colors
    @State private var dialog: WalletDialog?
    @State private var balanceDraft = ""
    @State private var initialRefreshComplete = false
    @State private var processingDates = Set<String>()
    @State private var trendToday = Date()
    @AppStorage("trendCollapsed") private var trendCollapsed = true

    private enum WalletDialog {
        case balance
        case detail(CampusBill)
        case deduct(CampusUnpaidBill, Double?)
        case deductAll([CampusUnpaidBill])
    }

    private var visibleBills: [CampusBill] { Array(model.bills.prefix(20)) }
    private var hasRealBalance: Bool { model.balance?.realBalance != nil }
    private var billsAvailable: Bool { initialRefreshComplete || !model.bills.isEmpty }
    private var balanceValue: Double? {
        guard var balance = model.balance else { return nil }
        guard hasRealBalance || billsAvailable else { return nil }
        balance.bills = visibleBills
        return balance.balance
    }
    private var balanceSource: String {
        if model.balance?.campusBalance != nil { return "来自校园卡账户的实时余额" }
        if hasRealBalance { return "来自趣智校园账户的实时余额" }
        return "仅通过初始金额和账单进行估算，并非真实余额"
    }
    private var modalPresented: Binding<Bool> {
        Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                balanceCard.padding(.bottom, 24)
                if model.preferences.trendEnabled {
                    OriginalSpendingTrendCard(bills: model.bills, loading: model.refreshing && !billsAvailable,
                                              today: trendToday, collapsed: $trendCollapsed,
                                              range: model.preferences.viewBinding(\.trendRange),
                                              chartType: model.preferences.viewBinding(\.trendType))
                        .padding(.bottom, 24)
                }
                billsSection
                Spacer(minLength: 100)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .refreshable { await model.refresh() }
        .task(id: model.auth.session?.ownerScope) {
            initialRefreshComplete = false
            dialog = nil
            guard model.auth.session != nil else { return }
            if !model.refreshing {
                await model.refresh()
                if !Task.isCancelled { initialRefreshComplete = true }
            }
        }
        .onChange(of: model.refreshing) { refreshing in
            if !refreshing, model.auth.session != nil { initialRefreshComplete = true }
        }
        .onChange(of: dialog != nil, perform: onModalVisibilityChanged)
        .onDisappear { if dialog != nil { onModalVisibilityChanged(false) } }
        .linYuModal(isPresented: modalPresented) { walletDialog }
        .accessibilityIdentifier("linyu.wallet")
    }

    private var balanceCard: some View {
        OriginalWalletBalanceCard(title: model.balance?.title ?? "余额", balance: balanceValue,
                                  source: balanceSource, onEdit: hasRealBalance ? nil : editBalance)
    }

    private func editBalance() {
        balanceDraft = balanceValue.map(OriginalFormatting.money)
            ?? (model.manualBalance.isEmpty ? "0" : model.manualBalance)
        dialog = .balance
    }

    private var deductibleBills: [CampusUnpaidBill] {
        var seen = Set<String>()
        return model.unpaid.filter { debt in
            guard debt.isDeductible, let date = debt.consumeDate else { return false }
            return seen.insert(date).inserted
        }
    }

    private var billsSection: some View {
        let bills = visibleBills
        let debts = deductibleBills
        let debtByDate = Dictionary(uniqueKeysWithValues: debts.compactMap { debt in
            debt.consumeDate.map { ($0, debt) }
        })
        let dates = Set(bills.map(\.consumeDate))
        let unmatched = model.unpaid.filter { debt in debt.consumeDate.map { !dates.contains($0) } ?? true }
        return VStack(alignment: .leading, spacing: 0) {
            OriginalWalletBillsHeading()
                .contextMenu {
                    if !debts.isEmpty {
                        Button("全部补扣") { dialog = .deductAll(debts) }
                            .disabled(model.isBusy || !processingDates.isEmpty)
                    }
                }
            if model.refreshing {
                OriginalWaterSpinner(size: 24, color: colors.accent)
                    .frame(maxWidth: .infinity).padding(24).padding(.top, 12)
            } else if bills.isEmpty {
                Text("暂无账单数据").font(LinYuType.font(16)).foregroundStyle(colors.textSecondary)
                    .padding(.top, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(bills) { bill in billRow(bill, debt: debtByDate[bill.consumeDate]) }
                }.padding(.top, 12)
            }
            if !unmatched.isEmpty {
                HStack {
                    Text("未扣账单").font(LinYuType.font(18, weight: .bold)).foregroundStyle(colors.textPrimary)
                    Spacer()
                    Button("全部补扣") { dialog = .deductAll(debts) }
                        .buttonStyle(.plain).font(LinYuType.font(13)).foregroundStyle(colors.accent)
                        .disabled(model.isBusy || !processingDates.isEmpty)
                }.padding(.top, 16).padding(.bottom, 8)
                VStack(spacing: 8) {
                    ForEach(unmatched) { debt in
                        OriginalGlassCard(padding: 14, cornerRadius: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.description ?? "未扣账单")
                                        .font(LinYuType.font(14, weight: .medium)).foregroundStyle(colors.textPrimary)
                                    Text(String((debt.consumeDate ?? "").prefix(16)))
                                        .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 6) {
                                    amountText(debt.consumeMoney ?? "—")
                                    deductButton(debt, amount: parsedAmount(debt.consumeMoney))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func billRow(_ bill: CampusBill, debt: CampusUnpaidBill?) -> some View {
        OriginalWalletBillRow(bill: bill, deduction: debt.map { deduction($0, amount: matchingAmount(bill, debt: $0)) },
                              onSelect: { dialog = .detail(bill) })
    }

    private func amountText(_ money: String) -> some View {
        Text("-¥ \(money)").font(LinYuType.font(16, weight: .bold)).foregroundStyle(colors.danger)
    }

    private func deductButton(_ debt: CampusUnpaidBill, amount: Double?) -> some View {
        OriginalWalletDeductButton(deduction: deduction(debt, amount: amount))
    }

    private func deduction(_ debt: CampusUnpaidBill, amount: Double?) -> OriginalWalletBillRow.Deduction {
        let processing = debt.consumeDate.map { processingDates.contains($0) } ?? false
        return .init(processing: processing, enabled: debt.isDeductible && !model.isBusy && processingDates.isEmpty,
                     action: { dialog = .deduct(debt, amount) })
    }

    @ViewBuilder private var walletDialog: some View {
        switch dialog {
        case .balance: balanceDialog
        case .detail(let bill): billDetail(bill).task(id: bill.id) { await model.loadDetail(bill) }
        case .deduct(let debt, let amount):
            OriginalDeductConfirmDialog(amount: amount, detail: debt.consumeDate ?? "",
                                       busy: model.isBusy || !deductibleBills.contains(debt) || currentAmount(debt) != amount,
                                       onConfirm: { confirmDeduction(debt, amount: amount) },
                                       onDismiss: { dialog = nil })
        case .deductAll(let debts):
            OriginalDeductConfirmDialog(amount: totalAmount(debts), detail: "共 \(debts.count) 笔",
                                       busy: model.isBusy || deductibleBills != debts,
                                       onConfirm: { confirmAll(debts) }, onDismiss: { dialog = nil })
        case nil: EmptyView()
        }
    }

    private var balanceDialog: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("手动填写余额").font(LinYuType.font(24, weight: .bold)).padding(.bottom, 16)
                Text("请输入账户当前余额").font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
                Text("此操作仅用于本地估算，不会修改账户真实余额")
                    .font(LinYuType.font(11)).foregroundStyle(colors.textSecondary).padding(.top, 4)
                TextField("余额 (元)", text: Binding(get: { balanceDraft }, set: updateDraft))
                    .keyboardType(.decimalPad).font(LinYuType.font(16)).padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.textSecondary, lineWidth: 1))
                    .padding(.top, 12).accessibilityLabel("余额 (元)")
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("取消") { dialog = nil }
                        .buttonStyle(.plain).foregroundStyle(colors.accent).padding(.horizontal, 12)
                    Button("保存") {
                        guard !hasRealBalance else { dialog = nil; return }
                        model.manualBalance = balanceDraft
                        model.setManualBalance()
                        dialog = nil
                    }.buttonStyle(LinYuButtonStyle())
                }.padding(.top, 24)
            }
        }
    }

    private func updateDraft(_ input: String) {
        if input.range(of: #"\A[0-9]{0,9}(\.[0-9]{0,2})?\z"#, options: .regularExpression) != nil {
            balanceDraft = input
        }
    }

    private func billDetail(_ bill: CampusBill) -> some View {
        let detail = model.billDetail.flatMap { $0.orderId == bill.orderId ? $0 : nil }
        return LinYuDialogCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("账单详情").font(LinYuType.font(24, weight: .bold))
                VStack(spacing: 0) {
                    detailLine("设备名", bill.displayDesc.isEmpty ? (detail?.description ?? "—") : bill.displayDesc)
                    detailLine("设备类型", bill.typeLabel)
                    detailLine("消费金额", "-¥ \(bill.consumeMoney)")
                    detailLine("消费时间", String(bill.consumeDate.prefix(19)))
                    detailLine("订单号", bill.orderId.isEmpty ? (detail?.orderNo ?? bill.orderNo ?? "—") : bill.orderId)
                }
                Button("确定") { dialog = nil }.buttonStyle(LinYuButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(LinYuType.font(14)).foregroundStyle(colors.textSecondary).fixedSize()
            Spacer(minLength: 0)
            Text(value).font(LinYuType.font(14, weight: .medium)).foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }.padding(.vertical, 4)
    }

    private func parsedAmount(_ text: String?) -> Double? {
        guard let text, let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func matchingAmount(_ bill: CampusBill, debt: CampusUnpaidBill) -> Double? {
        guard let amount = parsedAmount(bill.consumeMoney) else { return nil }
        if let debtMoney = debt.consumeMoney, parsedAmount(debtMoney) != amount { return nil }
        return amount
    }

    private func currentAmount(_ debt: CampusUnpaidBill) -> Double? {
        if let bill = visibleBills.first(where: { $0.consumeDate == debt.consumeDate }) {
            return matchingAmount(bill, debt: debt)
        }
        return parsedAmount(debt.consumeMoney)
    }

    private func totalAmount(_ debts: [CampusUnpaidBill]) -> Double? {
        guard !debts.isEmpty, debts.allSatisfy({ parsedAmount($0.consumeMoney) != nil }) else { return nil }
        return OriginalStartFailure(message: "", serverRejected: true).total(for: debts)
    }

    private func confirmDeduction(_ debt: CampusUnpaidBill, amount: Double?) {
        guard let amount, !model.isBusy, processingDates.isEmpty, let date = debt.consumeDate,
              let owner = model.auth.session?.ownerScope, deductibleBills.contains(debt),
              currentAmount(debt) == amount else { return }
        let visibleSnapshot = visibleBills
        let unpaidSnapshot = model.unpaid
        dialog = nil
        processingDates = [date]
        Task {
            defer { processingDates = [] }
            guard model.auth.session?.ownerScope == owner, !model.isBusy, model.unpaid == unpaidSnapshot,
                  visibleBills == visibleSnapshot, currentAmount(debt) == amount else { return }
            await model.deduct(debt)
        }
    }

    private func confirmAll(_ debts: [CampusUnpaidBill]) {
        guard let amount = totalAmount(debts), !model.isBusy, processingDates.isEmpty, deductibleBills == debts,
              let owner = model.auth.session?.ownerScope else { return }
        let unpaidSnapshot = model.unpaid
        dialog = nil
        processingDates = Set(debts.compactMap(\.consumeDate))
        Task {
            defer { processingDates = [] }
            guard model.auth.session?.ownerScope == owner, !model.isBusy, model.unpaid == unpaidSnapshot,
                  deductibleBills == debts, totalAmount(deductibleBills) == amount else { return }
            await model.deductAll()
        }
    }
}

struct OriginalWalletBalanceCard: View {
    let title: String
    let balance: Double?
    let source: String
    let onEdit: (() -> Void)?
    @Environment(\.linYuColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(LinYuType.font(22, weight: .bold)).foregroundStyle(colors.textPrimary)
            OriginalGlassCard(padding: 24, cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("账户余额 (元)").font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
                        Spacer()
                        if let onEdit {
                            Button(action: onEdit) {
                                Text("手动填写").font(LinYuType.font(13)).foregroundStyle(colors.accent)
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                                    .contentShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text(balance.map { "¥ " + OriginalFormatting.money($0) } ?? "¥ —")
                        .font(LinYuType.font(36, weight: .bold)).foregroundStyle(colors.textPrimary)
                        .padding(.top, 4)
                    Text(source).font(LinYuType.font(11)).foregroundStyle(colors.textSecondary)
                        .padding(.top, 8)
                }
            }
        }
    }
}

struct OriginalWalletBillsHeading: View {
    @Environment(\.linYuColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinYuSectionTitle(title: "账单")
            Text("最近20次消费记录").font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
        }
    }
}

struct OriginalWalletBillRow: View {
    struct Deduction {
        let processing: Bool
        let enabled: Bool
        let action: () -> Void
    }

    let bill: CampusBill
    let deduction: Deduction?
    let onSelect: () -> Void
    @Environment(\.linYuColors) private var colors

    var body: some View {
        OriginalGlassCard(padding: 0, cornerRadius: 14) {
            HStack(spacing: 8) {
                Button(action: onSelect) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(bill.emoji) \(bill.displayDesc)")
                                .font(LinYuType.font(14, weight: .medium)).foregroundStyle(colors.textPrimary)
                            Text(bill.typeLabel).font(LinYuType.font(12)).foregroundStyle(billColor)
                            Text(String(bill.consumeDate.prefix(16)))
                                .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if deduction == nil { amount }
                    }
                    .padding(.leading, 14).padding(.vertical, 14)
                    .padding(.trailing, deduction == nil ? 14 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if let deduction {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button(action: onSelect) { amount }.buttonStyle(.plain)
                        OriginalWalletDeductButton(deduction: deduction)
                    }.padding(.vertical, 14).padding(.trailing, 14)
                }
            }
        }
    }

    private var billColor: Color {
        if bill.isDrinkingWater { return Color(linYuHex: 0x10B981) }
        if bill.typeLabel.contains("洗手台") { return Color(linYuHex: 0xFF9800) }
        return colors.accent
    }

    private var amount: some View {
        Text("-¥ \(bill.consumeMoney)").font(LinYuType.font(16, weight: .bold)).foregroundStyle(colors.danger)
    }
}

private struct OriginalWalletDeductButton: View {
    let deduction: OriginalWalletBillRow.Deduction
    @Environment(\.linYuColors) private var colors

    var body: some View {
        Button(action: deduction.action) {
            Text(deduction.processing ? "扣款中…" : "请求代扣")
                .font(LinYuType.font(12)).foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 30)
                .background(deduction.processing ? colors.textSecondary.opacity(0.4) : colors.warning,
                            in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!deduction.enabled)
    }
}
