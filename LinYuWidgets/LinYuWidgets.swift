import SwiftUI
import WidgetKit

private struct WaterEntry: TimelineEntry { let date: Date; let snapshot: LinYuWidgetSnapshot }
private struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry { WaterEntry(date: .now, snapshot: LinYuWidgetSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) { completion(WaterEntry(date: .now, snapshot: LinYuWidgetStorage.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        let now = Date(); completion(Timeline(entries: [WaterEntry(date: now, snapshot: LinYuWidgetStorage.load())], policy: .after(now.addingTimeInterval(900))))
    }
}
private struct WaterWidgetView: View {
    let entry: WaterEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if #available(iOS 17.0, *) { content.containerBackground(.black.gradient, for: .widget) }
            else { content.padding(14).background(Color.black) }
        }.foregroundStyle(.white)
            .widgetURL(entry.snapshot.orders.first.map { LinYuWidgetStorage.url(action: "stop", id: $0.id, snapshot: entry.snapshot) } ?? LinYuWidgetStorage.url(action: "start", id: entry.snapshot.lastDeviceID, snapshot: entry.snapshot))
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("淋浴", systemImage: "drop.fill").font(.headline).foregroundStyle(.cyan); Spacer(); if family != .systemSmall { Text(entry.snapshot.balance).bold() } }
            if entry.snapshot.ownerScope.isEmpty { Text("打开应用登录").font(.subheadline); Spacer() }
            else if let order = entry.snapshot.orders.first {
                Text(order.title).font(.subheadline).lineLimit(2)
                Text(order.startedAt, style: .timer).font(.system(size: family == .systemSmall ? 26 : 34, weight: .light, design: .rounded)).monospacedDigit()
                Link(destination: LinYuWidgetStorage.url(action: "stop", id: order.id, snapshot: entry.snapshot)) { Text("结束使用").font(.caption.bold()).padding(.vertical, 7).frame(maxWidth: .infinity).background(.blue.opacity(0.65), in: Capsule()) }
                if family == .systemLarge {
                    ForEach(Array(entry.snapshot.orders.dropFirst().prefix(2))) { extra in HStack { Text(extra.title).font(.caption).lineLimit(1); Spacer(); Link("结束", destination: LinYuWidgetStorage.url(action: "stop", id: extra.id, snapshot: entry.snapshot)) } }
                }
            } else {
                if family == .systemSmall { Text(entry.snapshot.balance).font(.title2.bold()) }
                Text(entry.snapshot.lastDevice).font(.subheadline).lineLimit(2)
                if !entry.snapshot.lastDeviceID.isEmpty { Link(destination: LinYuWidgetStorage.url(action: "start", id: entry.snapshot.lastDeviceID, snapshot: entry.snapshot)) { Text("开始使用").font(.caption.bold()).padding(.vertical, 7).frame(maxWidth: .infinity).background(.blue.opacity(0.65), in: Capsule()) } }
            }
            if family == .systemLarge {
                Divider().overlay(.white.opacity(0.2))
                Text("最近账单").font(.caption).foregroundStyle(.secondary)
                ForEach(entry.snapshot.bills) { bill in HStack { Text(bill.title).lineLimit(1); Spacer(); Text("¥\(bill.amount)") }.font(.caption) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
@main struct LinYuWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LinYuWater", provider: WaterProvider()) { entry in WaterWidgetView(entry: entry) }
            .configurationDisplayName("淋浴").description("查看用水状态、余额和最近账单，打开应用快速启停。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
