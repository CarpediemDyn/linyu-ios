import SwiftUI

struct ProfileRelease: Decodable, Identifiable {
    let id: Int
    let tag: String
    let body: String?
    let publishedAt: String?
    let page: URL
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case id, body, prerelease, draft
        case tag = "tag_name"
        case publishedAt = "published_at"
        case page = "html_url"
    }

    var highlights: String {
        var result: [String] = []
        var including = false
        let lines = (body ?? "").replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let scalars = trimmed.drop(while: { $0 == "#" }).unicodeScalars.filter { scalar in
                    (0x4E00...0x9FFF).contains(scalar.value)
                        || (0x3000...0x303F).contains(scalar.value)
                        || (0x20...0x7E).contains(scalar.value)
                }
                let heading = scalars.map(String.init).joined().trimmingCharacters(in: .whitespaces)
                including = ["新增", "功能", "修复", "BUG"].contains { heading.localizedCaseInsensitiveContains($0) }
                if including {
                    if !result.isEmpty { result.append("") }
                    result.append(stripMarkup(heading))
                }
            } else if including {
                result.append(stripMarkup(line))
            }
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}

struct ProfileRepository: Decodable {
    struct Owner: Decodable { let login: String }
    let stars: Int
    let owner: Owner
    let page: URL

    enum CodingKeys: String, CodingKey {
        case stars = "stargazers_count"
        case owner
        case page = "html_url"
    }
}

@MainActor final class ProfileReleaseCatalog: ObservableObject {
    static let shared = ProfileReleaseCatalog()
    static let referenceVersion = "v3.1.0"
    static let repositoryURL = URL(string: "https://github.com/yehu-imei/linyu")!
    private static let api = URL(string: "https://api.github.com/repos/yehu-imei/linyu")!

    @Published private(set) var releases: [ProfileRelease] = []
    @Published private(set) var repository: ProfileRepository?
    @Published private(set) var checking = false
    @Published private(set) var checked = false
    private var requestedRepository = false

    func check() {
        guard !checking else { return }
        checking = true
        Task {
            defer {
                checking = false
                checked = true
            }
            var components = URLComponents(url: Self.api.appendingPathComponent("releases"),
                                           resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "per_page", value: "10")]
            guard let url = components?.url else { return }
            let fetched = await read([ProfileRelease].self, from: url)
            releases = fetched?.filter { !$0.prerelease && !$0.draft } ?? []
        }
    }

    func loadRepository() {
        guard !requestedRepository else { return }
        requestedRepository = true
        Task {
            repository = await read(ProfileRepository.self, from: Self.api)
        }
    }

    func isNewer(_ version: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
            while let first = cleaned.first, first == "v" || first == "V" { cleaned.removeFirst() }
            return cleaned.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" }).compactMap { Int($0) }
        }
        let latest = parts(version)
        let reference = parts(Self.referenceVersion)
        for index in 0..<max(latest.count, reference.count) {
            let left = index < latest.count ? latest[index] : 0
            let right = index < reference.count ? reference[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) async -> T? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("LinYu-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}

@MainActor struct ProfileAboutCard: View {
    @ObservedObject var catalog: ProfileReleaseCatalog
    @Environment(\.linYuColors) private var colors

    private var owner: String {
        let login = catalog.repository?.owner.login ?? ""
        return login.isEmpty ? "yehu-imei" : login
    }

    var body: some View {
        OriginalGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                ProfileCardTitle("关于项目")
                Text("LinYu iOS · 基于 LinYu 的 SwiftUI iOS 移植项目").padding(.top, 10)
                Text("iOS 移植与维护：Cra3y").padding(.top, 6)
                Text("Android 原版作者：\(owner)").padding(.top, 6)
                Text("应用名称：淋浴（Hualala）" + (catalog.repository.map { " · 原版 ⭐ \($0.stars)" } ?? ""))
                    .padding(.top, 6)
                Text("第三方客户端，不代表校园官方服务").padding(.top, 6)
                HStack(spacing: 0) {
                    Text("原版作者联系方式：")
                    Link("2276391153@qq.com", destination: URL(string: "mailto:2276391153@qq.com")!)
                        .foregroundStyle(colors.accent)
                }
                .padding(.top, 6)
                Link(destination: URL(string: "https://github.com/CarpediemDyn/linyu-ios")!) {
                    Text("访问 LinYu iOS 仓库").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 12))
                .padding(.top, 14)
                Link(destination: catalog.repository?.page ?? ProfileReleaseCatalog.repositoryURL) {
                    Text("访问 Android 原版仓库").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 12))
                .padding(.top, 14)
            }
            .font(LinYuType.font(13)).foregroundStyle(colors.textSecondary)
        }
        .onAppear { catalog.loadRepository() }
    }
}

@MainActor struct ProfileUpdateCard: View {
    @ObservedObject var catalog: ProfileReleaseCatalog
    @Environment(\.linYuColors) private var colors
    @State private var expandedTag: String?
    @State private var showAll = false

    private var latest: ProfileRelease? { catalog.releases.first }
    private var hasUpdate: Bool { latest.map { catalog.isNewer($0.tag) } ?? false }
    private var status: (text: String, color: Color) {
        if catalog.checking || !catalog.checked { return ("正在检测更新…", colors.textSecondary) }
        guard let latest else { return ("检测失败（多为网络原因）", colors.warning) }
        return hasUpdate ? ("发现新版本 \(latest.tag)", colors.accent) : ("当前已是最新版本", colors.success)
    }

    var body: some View {
        OriginalGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                ProfileCardTitle("应用信息")
                Text("当前版本 \(ProfileReleaseCatalog.referenceVersion)（Android 原版）")
                    .font(LinYuType.font(13)).foregroundStyle(colors.textSecondary).padding(.top, 4)
                Text(status.text).font(LinYuType.font(13, weight: .medium))
                    .foregroundStyle(status.color).padding(.top, 8)
                if !catalog.releases.isEmpty { releaseHistory }
                Button(action: catalog.check) {
                    Text(catalog.checking ? "检查中..." : "检查更新").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 12))
                .disabled(catalog.checking).padding(.top, 14)
                if hasUpdate, let latest { platformUpdate(latest) }
            }
        }
        .onAppear { if !catalog.checked { catalog.check() } }
    }

    private var releaseHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileDivider().padding(.top, 14)
            Text("更新日志").font(LinYuType.font(14, weight: .semibold))
                .foregroundStyle(colors.textPrimary).padding(.top, 10).padding(.bottom, 2)
            ForEach(showAll ? catalog.releases : Array(catalog.releases.prefix(3))) { release in
                releaseRow(release)
            }
            if catalog.releases.count > 3 {
                HStack {
                    Spacer()
                    ProfileTextAction(showAll ? "收起" : "展开全部", size: 12) { showAll.toggle() }
                    Spacer()
                }
            }
        }
    }

    private func releaseRow(_ release: ProfileRelease) -> some View {
        let expanded = expandedTag == release.tag
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedTag = expanded ? nil : release.tag
            } label: {
                HStack(spacing: 6) {
                    Text(release.tag).font(LinYuType.font(13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    if release.tag == ProfileReleaseCatalog.referenceVersion {
                        Text("当前").font(LinYuType.font(10)).foregroundStyle(colors.success)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(colors.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer()
                    LinYuIcon(name: expanded ? "keyboard_arrow_up" : "keyboard_arrow_down")
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                let highlights = release.highlights
                Text(highlights.isEmpty ? "本版本未填写更新详情。" : highlights)
                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.bottom, 6)
                if let publishedAt = release.publishedAt {
                    Text(String(publishedAt.prefix(10))).font(LinYuType.font(11))
                        .foregroundStyle(colors.textSecondary.opacity(0.7)).padding(.bottom, 6)
                }
                ProfileDivider()
            }
        }
    }

    private func platformUpdate(_ release: ProfileRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileDivider().padding(.bottom, 2)
            Text("此发布包适用于 Android。iOS 更新需要签名后的 iOS 分发版本。")
                .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
            Link(destination: release.page) { Text("查看发布页").frame(maxWidth: .infinity) }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 12))
        }
        .padding(.top, 12)
    }
}
