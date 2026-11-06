import Foundation

enum BackgroundScope: String, Codable, CaseIterable { case home, shower }

/// BackgroundState.BgConfig, with an immutable image revision for cache invalidation.
struct BackgroundConfiguration: Codable, Equatable {
    var enabled = false
    var imageFile = ""
    var opacity = 1.0
    var blur = 0.0
    var brightness = 1.0
    var themeColor: Int? = nil
    var imageVersion = UUID()

    mutating func normalize() {
        opacity = Self.clamp(opacity, to: 0.2...1, fallback: 1)
        blur = Self.clamp(blur, to: 0...20, fallback: 0)
        brightness = Self.clamp(brightness, to: 0.4...1.5, fallback: 1)
        if imageFile.isEmpty { enabled = false }
        if let themeColor, !(0...0xFFFFFF).contains(themeColor) { self.themeColor = nil }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    static func restore(scope: BackgroundScope, defaults: UserDefaults, directory: URL) -> Self {
        let key = "background.config.v2." + scope.rawValue
        var config: Self
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            config = decoded
        } else {
            let name = scope.rawValue
            let path = defaults.string(forKey: name == "home" ? "homeBackground" : "showerBackground") ?? ""
            config = Self()
            config.imageFile = path
            config.enabled = defaults.object(forKey: "background.\(name).enabled") as? Bool ?? !path.isEmpty
            config.opacity = defaults.object(forKey: "background.\(name).opacity") as? Double
                ?? (scope == .home ? defaults.object(forKey: "backgroundOpacity") as? Double : nil) ?? 1
            config.blur = defaults.object(forKey: "background.\(name).blur") as? Double
                ?? (scope == .home ? defaults.object(forKey: "backgroundBlur") as? Double : nil) ?? 0
            config.brightness = defaults.object(forKey: "background.\(name).brightness") as? Double ?? 1
            config.themeColor = defaults.object(forKey: "background.\(name).themeRGB") as? Int
        }
        // Rebase known old sandbox paths if LiveContainer moved the application container.
        if !config.imageFile.isEmpty {
            let candidate = directory.appendingPathComponent(URL(fileURLWithPath: config.imageFile).lastPathComponent)
            if FileManager.default.fileExists(atPath: candidate.path) { config.imageFile = candidate.lastPathComponent }
        }
        config.normalize()
        if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: key) }
        return config
    }
}
