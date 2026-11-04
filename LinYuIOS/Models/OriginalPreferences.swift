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
    @Published var backgroundScope = "home" {
        didSet {
            opacity = load("opacity", scope: backgroundScope, fallback: 1)
            blur = load("blur", scope: backgroundScope, fallback: 0)
            brightness = load("brightness", scope: backgroundScope, fallback: 1)
        }
    }
    @Published var homeBackground: String { didSet { defaults.set(homeBackground, forKey: "homeBackground") } }
    @Published var showerBackground: String { didSet { defaults.set(showerBackground, forKey: "showerBackground") } }
    @Published private(set) var homeThemeRGB: Int?
    @Published private(set) var showerThemeRGB: Int?
    var accentColor: Color {
        guard let rgb = homeThemeRGB else { return .blue }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "background.\(backgroundScope).opacity") } }
    @Published var blur: Double { didSet { defaults.set(blur, forKey: "background.\(backgroundScope).blur") } }
    @Published var brightness: Double { didSet { defaults.set(brightness, forKey: "background.\(backgroundScope).brightness") } }
    @Published var cardOrder: [String] { didSet { defaults.set(cardOrder, forKey: "profileCardOrder") } }
    @Published var hiddenCards: Set<String> { didSet { defaults.set(Array(hiddenCards), forKey: "profileHiddenCards") } }
    @Published var settingsOrder: [String] { didSet { defaults.set(settingsOrder, forKey: "settingsCardOrder") } }
    @Published var hiddenSettings: Set<String> { didSet { defaults.set(Array(hiddenSettings), forKey: "settingsHiddenCards") } }
    static let profileCards = ["账号信息", "使用码", "绑定寝室"]
    static let settingsCards = ["通知", "消费趋势", "背景装扮", "运行日志", "关于项目", "软件更新"]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: "themeMode") ?? "system"
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        notifyEnabled = flag("notifyEnabled"); notifyInUse = flag("notifyInUse")
        notifyFinished = flag("notifyFinished"); notifyAutoClose = flag("notifyAutoClose"); notifyAlert = flag("notifyAlert")
        trendEnabled = flag("trendEnabled"); trendRange = defaults.string(forKey: "trendRange") ?? "LAST_7_DAYS"
        trendType = defaults.string(forKey: "trendChartType") ?? "LINE"
        homeBackground = defaults.string(forKey: "homeBackground") ?? ""
        showerBackground = defaults.string(forKey: "showerBackground") ?? ""
        homeThemeRGB = defaults.object(forKey: "background.home.themeRGB") as? Int
        showerThemeRGB = defaults.object(forKey: "background.shower.themeRGB") as? Int
        opacity = defaults.object(forKey: "background.home.opacity") as? Double ?? defaults.object(forKey: "backgroundOpacity") as? Double ?? 1
        blur = defaults.object(forKey: "background.home.blur") as? Double ?? defaults.object(forKey: "backgroundBlur") as? Double ?? 0
        brightness = defaults.object(forKey: "background.home.brightness") as? Double ?? 1
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
    private func load(_ key: String, scope: String, fallback: Double) -> Double {
        defaults.object(forKey: "background.\(scope).\(key)") as? Double ?? fallback
    }
    func backgroundOpacity(shower: Bool) -> Double { let scope = shower ? "shower" : "home"; return scope == backgroundScope ? opacity : load("opacity", scope: scope, fallback: 1) }
    func backgroundBlur(shower: Bool) -> Double { let scope = shower ? "shower" : "home"; return scope == backgroundScope ? blur : load("blur", scope: scope, fallback: 0) }
    func backgroundBrightness(shower: Bool) -> Double { let scope = shower ? "shower" : "home"; return scope == backgroundScope ? brightness : load("brightness", scope: scope, fallback: 1) }
    func setBackground(_ data: Data, scope: String) throws {
        guard let image = OriginalBackgroundPalette.importedImage(data), let encoded = image.jpegData(compressionQuality: 0.95) else {
            throw WaterError.invalid("无法读取所选背景图片")
        }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true).appendingPathComponent("Backgrounds", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(scope == "shower" ? "shower.image" : "home.image")
        try encoded.write(to: file, options: .atomic)
        if scope == "shower" { showerBackground = file.path } else { homeBackground = file.path }
        resetTuning(scope: scope)
        let rgb = OriginalBackgroundPalette.rgb(image: image)
        setTheme(rgb, scope: scope)
    }
    func resetBackground(scope: String) {
        if scope == "shower" { showerBackground = "" } else { homeBackground = "" }
        resetTuning(scope: scope)
        setTheme(nil, scope: scope)
    }
    private func resetTuning(scope: String) {
        defaults.set(1.0, forKey: "background.\(scope).opacity")
        defaults.set(0.0, forKey: "background.\(scope).blur")
        defaults.set(1.0, forKey: "background.\(scope).brightness")
        if backgroundScope == scope { opacity = 1; blur = 0; brightness = 1 }
    }
    private func setTheme(_ rgb: Int?, scope: String) {
        if scope == "shower" { showerThemeRGB = rgb } else { homeThemeRGB = rgb }
        if let rgb { defaults.set(rgb, forKey: "background.\(scope).themeRGB") }
        else { defaults.removeObject(forKey: "background.\(scope).themeRGB") }
    }
}
