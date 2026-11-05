import Foundation
import Combine
import UserNotifications

@MainActor final class OriginalLogs: ObservableObject {
    static let shared = OriginalLogs()
    @Published private(set) var entries: [String] = []
    private let file: URL?
    init() {
        file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("linyu.log")
        if let file, let text = try? String(contentsOf: file, encoding: .utf8) { entries = Array(text.components(separatedBy: "\n").filter { !$0.isEmpty }.suffix(300)) }
    }
    func add(_ text: String) {
        let safe = text.replacingOccurrences(of: "(?i)(loginCode|password|smsCode|signature|clData)[\\\"'\\s:=]+[^\\s,}&]+", with: "$1=[已隐藏]", options: .regularExpression)
            .replacingOccurrences(of: "(?<![0-9])(1[0-9]{2})[0-9]{4}([0-9]{4})(?![0-9])", with: "$1****$2", options: .regularExpression)
        let entry = "\(Date().formatted(date: .omitted, time: .standard)) \(safe)"
        entries.append(entry); entries = Array(entries.suffix(300))
        if let file { try? entries.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8) }
    }
    func trace(_ operation: String) -> LatencyTrace {
        LatencyTrace(operation) { [weak self] line in
            Task { @MainActor in self?.add(line) }
        }
    }

    func export() -> URL? { file }
    func clear() { entries = []; if let file { try? "".write(to: file, atomically: true, encoding: .utf8) } }
}

@MainActor final class OriginalNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = OriginalNotifications()
    var onAction: ((URL) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var shown: [String: String] = [:]
    override init() {
        super.init(); center.delegate = self
        let stop = UNNotificationAction(identifier: "STOP_WATER", title: "结束用水", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "WATER_IN_USE", actions: [stop], intentIdentifiers: [])])
    }
    func requestPermission() async -> Bool { (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
    func post(id: String, title: String, text: String, url: URL?, active: Bool = false) {
        guard shown[id] != text else { return }; shown[id] = text
        let content = UNMutableNotificationContent(); content.title = title; content.body = text
        if let url { content.userInfo = ["url": url.absoluteString] }
        if active { content.categoryIdentifier = "WATER_IN_USE" } else { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { _ in }
    }
    func remove(id: String) {
        shown.removeValue(forKey: id)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
    func clear() {
        shown = [:]
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let text = response.notification.request.content.userInfo["url"] as? String
        if response.actionIdentifier != UNNotificationDismissActionIdentifier,
           let text, let url = URL(string: text) {
            if let routed = LinYuWidgetStorage.notificationURL(url, actionIdentifier: response.actionIdentifier) { Task { @MainActor in self.onAction?(routed) } }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
