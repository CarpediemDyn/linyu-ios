import Foundation

struct LinYuWidgetOrder: Codable, Identifiable {
    let id: String
    let title: String
    let startedAt: Date
    let isBluetooth: Bool
}
struct LinYuWidgetBill: Codable, Identifiable {
    let id: String
    let title: String
    let amount: String
}
struct LinYuWidgetSnapshot: Codable {
    var ownerScope = ""
    var updatedAt = Date()
    var balance = "¥ —"
    var balanceTitle = "余额"
    var lastDevice = "暂无上次设备"
    var lastDeviceID = ""
    var orders: [LinYuWidgetOrder] = []
    var bills: [LinYuWidgetBill] = []
    var controlNonce = UUID().uuidString
}
enum LinYuWidgetStorage {
    static var usesAppGroup: Bool {
#if LINYU_LIVECONTAINER
        return false
#else
        return true
#endif
    }
    private static var defaults: UserDefaults? { usesAppGroup ? UserDefaults(suiteName: group) : .standard }
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "LinYuAppGroup") as? String ?? "group.org.linyu.prototype" }
    static func load() -> LinYuWidgetSnapshot {
        guard let data = defaults?.data(forKey: "widget-snapshot"),
              let value = try? JSONDecoder().decode(LinYuWidgetSnapshot.self, from: data) else { return LinYuWidgetSnapshot() }
        return value
    }
    static func save(_ value: LinYuWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: "widget-snapshot")
    }
    static func url(action: String, id: String = "", snapshot supplied: LinYuWidgetSnapshot? = nil) -> URL {
        var parts = URLComponents(); parts.scheme = "linyu"; parts.host = action
        let snapshot = supplied ?? load()
        parts.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "owner", value: snapshot.ownerScope), URLQueryItem(name: "nonce", value: snapshot.controlNonce)]
        return parts.url!
    }
    /// Android's widget_root opens the app; only explicitly labelled control links operate valves.
    static func bodyURL(snapshot: LinYuWidgetSnapshot) -> URL {
        url(action: "show", id: snapshot.orders.first?.id ?? "", snapshot: snapshot)
    }
    static func notificationURL(_ url: URL, actionIdentifier: String) -> URL? {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.host = actionIdentifier == "STOP_WATER" ? "stop" : "show"
        return parts?.url
    }
}
