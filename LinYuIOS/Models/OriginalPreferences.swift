import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor final class OriginalPreferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var theme: String { didSet { defaults.set(theme, forKey: "themeMode") } }
    @Published var notifyEnabled: Bool { didSet { defaults.set(notifyEnabled, forKey: "notifyEnabled") } }
    @Published var notifyInUse: Bool { didSet { defaults.set(notifyInUse, forKey: "notifyInUse") } }
    @Published var notifyFinished: Bool { didSet { defaults.set(notifyFinished, forKey: "notifyFinished") } }
    @Published var notifyAutoClose: Bool { didSet { defaults.set(notifyAutoClose, forKey: "notifyAutoClose") } }
    @Published var notifyAlert: Bool { didSet { defaults.set(notifyAlert, forKey: "notifyAlert") } }
    @Published var trendEnabled: Bool { didSet { defaults.set(trendEnabled, forKey: "trendEnabled") } }
    @Published var trendRange: String { didSet { defaults.set(trendRange, forKey: "trendRange") } }
    @Published var trendType: String { didSet { defaults.set(trendType, forKey: "trendChartType") } }
    @Published private(set) var homeBackgroundConfig: BackgroundConfiguration
    @Published private(set) var showerBackgroundConfig: BackgroundConfiguration
    @Published var backgroundSelection: BackgroundScope { didSet { defaults.set(backgroundSelection.rawValue, forKey: "backgroundScope") } }
    enum BackgroundImportState: Equatable { case loading, failed(String) }
    @Published private(set) var backgroundImports: [BackgroundScope: BackgroundImportState] = [:]
    let backgroundImages: BackgroundImageStore
    let backgroundDirectory: URL
    struct BackgroundImportHandle { let id: UUID; let completion: Task<Void, Never> }
    private var backgroundJobs: [BackgroundScope: BackgroundImportHandle] = [:]

    // Compatibility accessors read one config; changing the selection never writes its effects.
    var backgroundScope: String {
        get { backgroundSelection.rawValue }
        set { backgroundSelection = BackgroundScope(rawValue: newValue) ?? .home }
    }
    var homeBackground: String { backgroundURL(for: .home)?.path ?? "" }
    var showerBackground: String { backgroundURL(for: .shower)?.path ?? "" }
    var homeThemeRGB: Int? { homeBackgroundConfig.enabled ? homeBackgroundConfig.themeColor : nil }
    var showerThemeRGB: Int? { showerBackgroundConfig.enabled ? showerBackgroundConfig.themeColor : nil }
    var accentColor: Color { Color(linYuHex: UInt32(homeThemeRGB ?? (theme == "dark" ? 0x58A6FF : 0x2563EB))) }
    var opacity: Double {
        get { configuration(for: backgroundSelection).opacity }
        set { setEffect(newValue, at: \.opacity, scope: backgroundSelection) }
    }
    var blur: Double {
        get { configuration(for: backgroundSelection).blur }
        set { setEffect(newValue, at: \.blur, scope: backgroundSelection) }
    }
    var brightness: Double {
        get { configuration(for: backgroundSelection).brightness }
        set { setEffect(newValue, at: \.brightness, scope: backgroundSelection) }
    }
    @Published var cardOrder: [String] { didSet { defaults.set(cardOrder, forKey: "profileCardOrder") } }
    @Published var hiddenCards: Set<String> { didSet { defaults.set(Array(hiddenCards), forKey: "profileHiddenCards") } }
    @Published var settingsOrder: [String] { didSet { defaults.set(settingsOrder, forKey: "settingsCardOrder") } }
    @Published var hiddenSettings: Set<String> { didSet { defaults.set(Array(hiddenSettings), forKey: "settingsHiddenCards") } }
    static let profileCards = ["账号信息", "使用码", "绑定寝室"]
    static let settingsCards = ["通知", "消费趋势", "背景装扮", "运行日志", "关于项目", "软件更新"]
    init(defaults: UserDefaults = .standard, backgroundDirectory: URL? = nil) {
        self.defaults = defaults
        let directory = backgroundDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("Backgrounds", isDirectory: true)
        self.backgroundDirectory = directory
        backgroundImages = BackgroundImageStore(directory: directory)
        homeBackgroundConfig = .restore(scope: .home, defaults: defaults, directory: directory)
        showerBackgroundConfig = .restore(scope: .shower, defaults: defaults, directory: directory)
        backgroundSelection = BackgroundScope(rawValue: defaults.string(forKey: "backgroundScope") ?? "") ?? .home
        theme = defaults.string(forKey: "themeMode") ?? "light"
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        notifyEnabled = flag("notifyEnabled"); notifyInUse = flag("notifyInUse")
        notifyFinished = flag("notifyFinished"); notifyAutoClose = flag("notifyAutoClose"); notifyAlert = flag("notifyAlert")
        trendEnabled = flag("trendEnabled"); trendRange = defaults.string(forKey: "trendRange") ?? "LAST_7_DAYS"
        trendType = defaults.string(forKey: "trendChartType") ?? "LINE"
        let known = Set(Self.profileCards + Self.settingsCards)
        var assigned = Set<String>()
        var profile = (defaults.stringArray(forKey: "profileCardOrder") ?? []).filter { known.contains($0) && assigned.insert($0).inserted }
        var settings = (defaults.stringArray(forKey: "settingsCardOrder") ?? []).filter { known.contains($0) && assigned.insert($0).inserted }
        for value in Self.profileCards where assigned.insert(value).inserted { profile.append(value) }
        for value in Self.settingsCards where assigned.insert(value).inserted { settings.append(value) }
        cardOrder = profile
        hiddenCards = Set(defaults.stringArray(forKey: "profileHiddenCards") ?? [])
        settingsOrder = settings
        hiddenSettings = Set(defaults.stringArray(forKey: "settingsHiddenCards") ?? [])
    }
    func configuration(for scope: BackgroundScope) -> BackgroundConfiguration {
        scope == .home ? homeBackgroundConfig : showerBackgroundConfig
    }

    func backgroundURL(for scope: BackgroundScope) -> URL? {
        let config = configuration(for: scope)
        guard config.enabled, !config.imageFile.isEmpty else { return nil }
        if config.imageFile.hasPrefix("/") { return URL(fileURLWithPath: config.imageFile) }
        guard config.imageFile == URL(fileURLWithPath: config.imageFile).lastPathComponent else { return nil }
        return backgroundDirectory.appendingPathComponent(config.imageFile)
    }

    func backgroundOpacity(shower: Bool) -> Double { configuration(for: shower ? .shower : .home).opacity }
    func backgroundBlur(shower: Bool) -> Double { configuration(for: shower ? .shower : .home).blur }
    func backgroundBrightness(shower: Bool) -> Double { configuration(for: shower ? .shower : .home).brightness }

    func backgroundBinding(_ path: WritableKeyPath<BackgroundConfiguration, Double>, scope: BackgroundScope) -> Binding<Double> {
        Binding(get: { self.configuration(for: scope)[keyPath: path] },
                set: { self.setEffect($0, at: path, scope: scope) })
    }

    private func setEffect(_ value: Double, at path: WritableKeyPath<BackgroundConfiguration, Double>, scope: BackgroundScope) {
        var config = configuration(for: scope)
        config[keyPath: path] = value
        saveBackground(config, scope: scope)
    }

    private func saveBackground(_ value: BackgroundConfiguration, scope: BackgroundScope) {
        var config = value
        config.normalize()
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: "background.config.v2." + scope.rawValue)
        if scope == .home { homeBackgroundConfig = config } else { showerBackgroundConfig = config }
    }

    /// Captures the destination before the picker/iCloud read yields. New imports and reset
    /// invalidate the previous job; only the current job may commit the saved file/config.
    @discardableResult
    func beginBackgroundImport(scope: BackgroundScope, load: @escaping @MainActor () async throws -> URL?) -> BackgroundImportHandle {
        cancelBackgroundImport(scope: scope)
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            let started = DispatchTime.now().uptimeNanoseconds
            var staged: URL?
            defer { if let staged { BackgroundPhoto.removeStaged(staged) } }
            do {
                OriginalLogs.shared.add("BACKGROUND import_started scope=\(scope.rawValue)")
                staged = try await load()
                try Task.checkCancellation()
                guard let staged else { throw BackgroundImageStore.Failure.photoUnavailable }
                let image = try await self.backgroundImages.prepare(source: staged, scope: scope)
                guard !Task.isCancelled, self.backgroundJobs[scope]?.id == id else {
                    await self.backgroundImages.removeOwnedImage(at: self.backgroundDirectory.appendingPathComponent(image.fileName))
                    return
                }
                let previous = self.backgroundURL(for: scope)
                var config = BackgroundConfiguration()
                config.enabled = true
                config.imageFile = image.fileName
                config.themeColor = image.themeColor
                self.saveBackground(config, scope: scope)
                let total = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                OriginalLogs.shared.add("BACKGROUND import_completed scope=\(scope.rawValue) processing=\(image.durationMilliseconds)ms total=\(total)ms")
                await self.backgroundImages.removeOwnedImage(at: previous)
                if self.backgroundJobs[scope]?.id == id {
                    self.backgroundJobs[scope] = nil
                    self.backgroundImports[scope] = nil
                }
            } catch {
                guard self.backgroundJobs[scope]?.id == id else { return }
                self.backgroundJobs[scope] = nil
                if error is CancellationError || Task.isCancelled { self.backgroundImports[scope] = nil }
                else {
                    let message = (error as? BackgroundImageStore.Failure)?.localizedDescription
                        ?? BackgroundImageStore.Failure.photoUnavailable.localizedDescription
                    self.backgroundImports[scope] = .failed(message)
                    OriginalLogs.shared.add("BACKGROUND import_failed scope=\(scope.rawValue)")
                }
            }
        }
        let handle = BackgroundImportHandle(id: id, completion: task)
        backgroundJobs[scope] = handle
        backgroundImports[scope] = .loading
        return handle
    }

    func cancelBackgroundImport(scope: BackgroundScope, matching id: UUID? = nil) {
        guard let job = backgroundJobs[scope], id == nil || job.id == id else { return }
        backgroundJobs[scope] = nil
        job.completion.cancel()
        backgroundImports[scope] = nil
    }

    func resetBackground(scope raw: String) { resetBackground(scope: BackgroundScope(rawValue: raw) ?? .home) }

    func resetBackground(scope: BackgroundScope) {
        cancelBackgroundImport(scope: scope)
        let previous = backgroundURL(for: scope)
        saveBackground(BackgroundConfiguration(), scope: scope)
        backgroundImports[scope] = nil
        Task { await backgroundImages.removeOwnedImage(at: previous) }
    }
}
