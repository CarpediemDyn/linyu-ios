import SwiftUI

@MainActor struct OriginalSpendingTrendCard: View {
    let bills: [CampusBill]
    let loading: Bool
    let today: Date
    @Binding var collapsed: Bool
    @Binding var range: String
    @Binding var chartType: String
    @Environment(\.linYuColors) private var colors
    @State private var selectedIndex: Int?

    private var thisMonth: Bool { range == "THIS_MONTH" }
    private var barChart: Bool { chartType == "BAR" }

    var body: some View {
        OriginalGlassCard(padding: 18, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("消费趋势").font(LinYuType.font(18, weight: .bold)).foregroundStyle(colors.textPrimary)
                    Spacer()
                    Button { collapsed.toggle() } label: {
                        LinYuIcon(name: collapsed ? "keyboard_arrow_down" : "keyboard_arrow_up")
                            .foregroundStyle(colors.textSecondary).frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(collapsed ? "展开消费趋势" : "折叠消费趋势")
                }
                if !collapsed {
                    let points = dailySpend()
                    let total = points.reduce(0) { $0 + $1.amount }
                    let count = points.reduce(0) { $0 + $1.count }
                    HStack(spacing: 0) {
                        metric("总消费", value: money(total))
                        metric("消费次数", value: "\(count) 次")
                        metric("单次平均", value: money(count == 0 ? 0 : total / Double(count)))
                    }.padding(.top, 18).padding(.bottom, 18)
                    if loading {
                        OriginalWaterSpinner(size: 24, color: colors.accent)
                            .frame(maxWidth: .infinity).frame(height: 190)
                    } else {
                        controls(points: points)
                        chart(points: points)
                        axis(points: points)
                    }
                }
            }
        }
        .onChange(of: range) { _ in selectedIndex = nil }
        .accessibilityIdentifier("linyu.wallet.trend")
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(LinYuType.font(11)).foregroundStyle(colors.textSecondary)
            Text(value).font(LinYuType.font(15, weight: .semibold)).foregroundStyle(colors.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controls(points: [DailySpend]) -> some View {
        let point = selectedIndex.flatMap { points.indices.contains($0) ? points[$0] : nil }
        return GeometryReader { geometry in
            let width = max(0, (geometry.size.width - 4) / 3)
            HStack(spacing: 0) {
                Text(point.map { "\(shortDate($0.date))  \(money($0.amount)) · \($0.count)次" } ?? "每日明细")
                    .font(LinYuType.font(12, weight: point == nil ? .regular : .medium))
                    .foregroundStyle(point == nil ? colors.textSecondary : colors.textPrimary)
                    .lineLimit(1).frame(width: width, alignment: .leading)
                HStack(spacing: 0) {
                    segment("7天", active: !thisMonth, medium: true) { range = "LAST_7_DAYS" }
                    segment("本月", active: thisMonth, medium: true) { range = "THIS_MONTH" }
                }.frame(width: width)
                Spacer(minLength: 4).frame(width: 4)
                HStack(spacing: 0) {
                    segment("柱形", active: barChart, medium: false) { chartType = "BAR" }
                    segment("折线", active: !barChart, medium: false) { chartType = "LINE" }
                }.frame(width: width)
            }.frame(height: 32)
        }.frame(height: 32)
    }

    private func segment(_ title: String, active: Bool, medium: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(LinYuType.font(11, weight: medium && active ? .medium : .regular))
                .foregroundStyle(active ? colors.accent : colors.textSecondary).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(active ? colors.accent.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
    }

    private func chart(points: [DailySpend]) -> some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !points.isEmpty, size.width > 0 else { return }
                let bottom = size.height - 10
                let maxAmount = max(1, points.map(\.amount).max() ?? 0)
                let barWidth = size.width / CGFloat(points.count) * 0.58
                let inset = min(size.width / 2, barChart ? max(barWidth / 2, 5) : 5)
                let positions = points.enumerated().map { index, point in
                    let x = points.count == 1 ? size.width / 2
                        : inset + CGFloat(index) / CGFloat(points.count - 1) * (size.width - 2 * inset)
                    let y = bottom - (size.height - 20) * CGFloat(point.amount / maxAmount)
                    return CGPoint(x: x, y: y)
                }
                if barChart {
                    for position in positions where position.y < bottom {
                        let rect = CGRect(x: position.x - barWidth / 2, y: position.y,
                                          width: barWidth, height: bottom - position.y)
                        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(colors.accent.opacity(0.72)))
                    }
                } else if let first = positions.first {
                    var area = Path()
                    area.move(to: CGPoint(x: 0, y: bottom))
                    area.addLines([CGPoint(x: 0, y: bottom)] + positions + [CGPoint(x: size.width, y: bottom)])
                    area.closeSubpath()
                    context.fill(area, with: .color(colors.accent.opacity(0.10)))
                    var line = Path()
                    line.move(to: first)
                    line.addLines(positions)
                    context.stroke(line, with: .color(colors.accent), lineWidth: 2.5)
                }
                for (index, position) in positions.enumerated() {
                    let selected = selectedIndex == index
                    context.fill(dot(at: position, radius: selected ? 5 : 3), with: .color(colors.accent))
                    context.fill(dot(at: position, radius: selected ? 2 : 1), with: .color(colors.card))
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { event in
                guard !points.isEmpty, geometry.size.width > 0 else { return }
                let index = Int((event.location.x / geometry.size.width * CGFloat(points.count - 1)).rounded())
                selectedIndex = min(max(0, index), points.count - 1)
            })
            .accessibilityLabel("消费趋势图")
            .accessibilityValue(selectedIndex.flatMap { points.indices.contains($0) ? points[$0] : nil }
                .map { "\(shortDate($0.date)) \(money($0.amount))，\($0.count)次" } ?? "每日明细")
            .accessibilityAdjustableAction { direction in
                guard !points.isEmpty else { return }
                switch direction {
                case .increment: selectedIndex = min((selectedIndex ?? -1) + 1, points.count - 1)
                case .decrement: selectedIndex = max((selectedIndex ?? 1) - 1, 0)
                @unknown default: break
                }
            }
        }.frame(height: 146)
    }

    private func dot(at position: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius, width: 2 * radius, height: 2 * radius))
    }

    private func axis(points: [DailySpend]) -> some View {
        let indices = axisIndices(count: points.count)
        return HStack(spacing: 0) {
            ForEach(indices, id: \.self) { index in
                Text(shortDate(points[index].date)).font(LinYuType.font(10)).foregroundStyle(colors.textSecondary)
                if index != indices.last { Spacer(minLength: 0) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func axisIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 5 { return Array(Set([0, count / 2, count - 1])).sorted() }
        return (0..<5).map { $0 * (count - 1) / 4 }
    }

    private func money(_ amount: Double) -> String { "¥" + OriginalFormatting.money(amount) }

    private func shortDate(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }

    private func dailySpend() -> [DailySpend] {
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.startOfDay(for: today)
        let start: Date
        if thisMonth {
            start = calendar.dateInterval(of: .month, for: today)?.start ?? end
        } else {
            start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        }
        var days: [Date: DailySpend] = [:]
        for bill in bills {
            guard let date = bill.date, let amount = Double(bill.consumeMoney), amount.isFinite, amount >= 0 else { continue }
            let day = calendar.startOfDay(for: date)
            guard day >= start, day <= end else { continue }
            days[day, default: DailySpend(date: day)].amount += amount
            days[day, default: DailySpend(date: day)].count += 1
        }
        var result: [DailySpend] = []
        var day = start
        while day <= end {
            result.append(days[day] ?? DailySpend(date: day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private struct DailySpend {
        let date: Date
        var amount: Double = 0
        var count: Int = 0
    }
}

struct OriginalWaterSpinner: View {
    let size: CGFloat
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                spinner(degrees: -90)
            } else {
                TimelineView(.animation) { timeline in
                    let fraction = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                    spinner(degrees: fraction * 360)
                }
            }
        }.frame(width: size, height: size).accessibilityLabel("正在加载")
    }

    private func spinner(degrees: Double) -> some View {
        Circle().trim(from: 0, to: 0.72).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(degrees))
    }
}
