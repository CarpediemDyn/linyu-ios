import SwiftUI
import PhotosUI

private enum OriginalPanel: String, Identifiable { case settings, room, account, background, logs, cards, updates, about; var id: String { rawValue } }

@MainActor struct OriginalProfileView: View {
    @ObservedObject var model: OriginalAppModel
    @State private var panel: OriginalPanel?
    @State private var logoutConfirmation = false
    @State private var candidateSheet = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("我的").font(.largeTitle.bold()); Spacer(); Button { withAnimation { model.preferences.theme = model.preferences.theme == "dark" ? "light" : "dark" } } label: { Image(systemName: model.preferences.theme == "dark" ? "moon.fill" : "sun.max.fill") }; Button { panel = .settings } label: { Image(systemName: "gearshape.fill") } }.font(.title2)
                    ForEach(model.preferences.cardOrder.filter { !model.preferences.hiddenCards.contains($0) }, id: \.self) { card in cardBody(card) }
                    Button("编辑卡片") { panel = .cards }.font(.caption).frame(maxWidth: .infinity)
                    Button("退出登录", role: .destructive) {
                        if !model.activeBluetooth.isEmpty || !model.cloud.active.isEmpty { logoutConfirmation = true } else { model.auth.logout() }
                    }.frame(maxWidth: .infinity).padding(.vertical, 18).disabled(model.isBusy)
                }.padding(20)
            }.refreshable { await model.refresh() }.toolbar(.hidden, for: .navigationBar)
            .sheet(item: $panel) { item in
                switch item {
                case .settings: OriginalSettingsView(model: model)
                case .room: OriginalRoomPicker(model: model)
                case .account: OriginalAccountManagement(model: model)
                case .background: OriginalBackgroundSettings(model: model)
                case .logs: OriginalLogView(logs: model.logs)
                case .cards: OriginalCardEditor(preferences: model.preferences)
                case .updates: OriginalUpdateView()
                case .about: OriginalAboutView()
                }
            }
            .sheet(isPresented: $candidateSheet) { OriginalCodeCandidateView(model: model) }
            .alert("仍有用水中的设备", isPresented: $logoutConfirmation) { Button("返回", role: .cancel) {}; Button("确认退出", role: .destructive) { model.auth.logout() } } message: { Text("退出后不会自动关阀，请先确认用水状态。未完成记录会保留，重新登录原账号后可恢复。") }
        }
    }
    private var maskedPhone: String {
        let phone = model.auth.session?.telephone ?? ""
        return phone.count >= 7 ? "\(phone.prefix(3))****\(phone.suffix(4))" : phone
    }
    @ViewBuilder private func cardBody(_ card: String) -> some View {
        switch card {
        case "账号信息":
            OriginalGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: "person.crop.circle.fill").font(.system(size: 46)).foregroundStyle(model.preferences.accentColor); VStack(alignment: .leading, spacing: 4) { Text(model.account?.profile.name ?? "趣智校园用户").font(.title3.bold()); Text(model.account?.profile.studentNumber ?? maskedPhone).font(.subheadline).foregroundStyle(.secondary) }; Spacer() }
                    if let school = model.account?.profile.schoolName { LabeledContent("学校", value: school) }
                    if let student = model.account?.profile.studentNumber { LabeledContent("学号", value: student) }
                    Button("账号管理") { panel = .account }
                }
            }
        case "使用码":
            OriginalGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("使用码").font(.headline); Spacer(); Toggle("启用", isOn: Binding(get: { model.account?.useCode.useCodeStatus == 1 }, set: { value in Task { await model.toggleCode(value) } })).labelsHidden().disabled(model.isBusy) }
                    if let code = model.account?.useCode.useCode, !code.isEmpty {
                        (Text(String(code.dropLast(3))) + Text(String(code.suffix(3))).foregroundColor(.blue)).font(.system(size: 34, weight: .bold, design: .monospaced)).textSelection(.enabled)
                    } else { Text("尚未领取").foregroundStyle(.secondary) }
                    Button("领取 / 重新领取") {
                        if model.account?.useCode.resetAvailability == 0 { model.message = model.account?.useCode.resetAvailabilityWarMark ?? "暂不可重新领取" }
                        else { candidateSheet = true; Task { await model.generateCode() } }
                    }.disabled(model.isBusy)
                }
            }
        case "绑定寝室":
            OriginalGlassCard { VStack(alignment: .leading, spacing: 12) { Text("绑定寝室").font(.headline); Text((model.account?.boundRoom ?? "").isEmpty ? "未绑定寝室，显示全部设备" : model.account?.boundRoom ?? "").foregroundStyle(.secondary); HStack { Button("选择附近") { panel = .room }; Spacer(); if !(model.account?.boundRoom ?? "").isEmpty { Button("取消绑定", role: .destructive) { model.bindRoom("") } } } } }
        case "通知": OriginalGlassCard { VStack(alignment: .leading) { Toggle("通知", isOn: model.preferences.viewBinding(\.notifyEnabled)); if model.preferences.notifyEnabled { Toggle("用水中", isOn: model.preferences.viewBinding(\.notifyInUse)); Toggle("用水结束", isOn: model.preferences.viewBinding(\.notifyFinished)); Toggle("自动关闭", isOn: model.preferences.viewBinding(\.notifyAutoClose)); Toggle("异常提醒", isOn: model.preferences.viewBinding(\.notifyAlert)); Button("允许系统通知") { Task { _ = await OriginalNotifications.shared.requestPermission() } } } } }
        case "消费趋势": OriginalGlassCard { VStack(alignment: .leading) { Toggle("消费趋势", isOn: model.preferences.viewBinding(\.trendEnabled)); Picker("图表", selection: model.preferences.viewBinding(\.trendType)) { Text("折线").tag("LINE"); Text("柱状").tag("BAR") } } }
        case "背景装扮": shortcut(card, "photo.on.rectangle.angled", .background)
        case "软件更新": shortcut(card, "arrow.down.circle", .updates)
        case "运行日志": shortcut(card, "doc.text", .logs)
        default: shortcut("关于项目", "info.circle", .about)
        }
    }
    private func shortcut(_ text: String, _ symbol: String, _ target: OriginalPanel) -> some View {
        Button { panel = target } label: { OriginalGlassCard { HStack { Label(text, systemImage: symbol).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) } } }.buttonStyle(.plain)
    }
}

@MainActor private struct OriginalCodeCandidateView: View {
    @ObservedObject var model: OriginalAppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("领取使用码").font(.title2.bold())
                if model.candidateWorking { ProgressView() }
                if let candidate = model.codeCandidate {
                    Text(candidate.useCode).font(.system(size: 38, weight: .bold, design: .monospaced)).textSelection(.enabled)
                    Text("今天还可换 \(candidate.remainTimes) 次").foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text("请在 \(max(0, 180 - Int(Date().timeIntervalSince(model.candidateCreatedAt ?? .now)))) 秒内领取").font(.caption) }
                    Button("换一个") { Task { await model.generateCode() } }.disabled(model.candidateWorking)
                    Button("确定领取") { Task { await model.claimCode(); if model.candidateClaimed { dismiss() } } }.buttonStyle(.borderedProminent).disabled(model.candidateWorking)
                }
                Text("预览不会替换当前使用码，确定领取后才生效。取消不会修改现有码。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(model.message).font(.footnote)
            }.padding(28).navigationTitle("使用码").toolbar { Button("取消") { model.codeCandidate = nil; dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}

@MainActor struct OriginalRoomPicker: View {
    @ObservedObject var model: OriginalAppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.ble.meters.isEmpty { Text("先扫描附近设备，再选择所在寝室") }
                ForEach(model.ble.meters) { meter in
                    Button {
                        Task {
                            await model.choose(meter, showDetail: false)
                            if let device = model.nearby[meter.id] { model.bindRoom(device.deviceName); dismiss() }
                        }
                    } label: { VStack(alignment: .leading) { Text(model.nearby[meter.id].flatMap { OriginalFormatting.roomKey($0.deviceName) } ?? meter.name); Text("\(meter.rssi) dBm").font(.caption).foregroundStyle(.secondary) } }.disabled(model.isBusy)
                }
            }.navigationTitle("选择附近寝室").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .primaryAction) { Button("扫描") { model.ble.startScan() }.disabled(model.isBusy) } }
        }
    }
}

@MainActor struct OriginalAccountManagement: View {
    @ObservedObject var model: OriginalAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var phoneCode = ""
    @State private var oldPassword = ""
    @State private var password = ""
    @State private var resetCode = ""
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("更换手机号") {
                    TextField("新手机号", text: $phone).keyboardType(.phonePad)
                    TextField("发到新手机号的验证码", text: $phoneCode).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    Button("向新手机号发送验证码") { act { session in try await model.api.sendAccountSMS(to: phone, purpose: .newPhone, session: session); message = "验证码已发送" } }
                    Button("确认更换") { act { session in try await model.api.updatePhone(newTelephone: phone, code: phoneCode, session: session); try model.auth.replaceSession(QzxySession(telephone: phone, loginCode: session.loginCode, userId: session.userId, accountId: session.accountId, projectId: session.projectId)); message = "手机号已更新" } }
                }
                Section("修改密码") {
                    SecureField("旧密码", text: $oldPassword).textContentType(.password)
                    SecureField("新密码", text: $password).textContentType(.newPassword)
                    Button("修改密码") { act { session in try await model.api.updatePassword(oldPassword: oldPassword, newPassword: password, session: session); oldPassword = ""; password = ""; message = "密码已更新" } }
                }
                Section("没有密码 / 忘记密码") {
                    TextField("当前手机号的验证码", text: $resetCode).keyboardType(.numberPad)
                    SecureField("重置后的新密码", text: $password).textContentType(.newPassword)
                    Button("向当前手机号发送验证码") { act { session in try await model.api.sendAccountSMS(to: session.telephone, purpose: .forgotPassword, session: session); message = "验证码已发送" } }
                    Button("重置密码") { act { session in try await model.api.forgetPassword(password: password, code: resetCode, session: session); password = ""; resetCode = ""; message = "密码已重置" } }
                }
                if busy { ProgressView() }
                if !message.isEmpty { Text(message) }
            }.disabled(busy || model.isBusy).navigationTitle("账号管理").toolbar { Button("关闭") { dismiss() } }
        }
    }
    private func act(_ work: @escaping (QzxySession) async throws -> Void) {
        guard !busy, let session = model.auth.session else { return }; busy = true
        model.auth.transactionInProgress = true
        Task { defer { busy = false; model.auth.transactionInProgress = false }; do { try await work(session) } catch { message = error.localizedDescription; model.logs.add(message) } }
    }
}

@MainActor struct OriginalSettingsView: View {
    @ObservedObject var model: OriginalAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var panel: OriginalPanel?
    @State private var candidateSheet = false
    var body: some View {
        NavigationStack {
            Form {
                Section("外观") { Picker("主题", selection: model.preferences.viewBinding(\.theme)) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") } }
                ForEach(model.preferences.settingsOrder.filter { !model.preferences.hiddenSettings.contains($0) }, id: \.self) { title in
                    Section(title) {
                        switch title {
                        case "通知":
                            Toggle("通知", isOn: model.preferences.viewBinding(\.notifyEnabled))
                            if model.preferences.notifyEnabled {
                                Toggle("用水中", isOn: model.preferences.viewBinding(\.notifyInUse)); Toggle("用水结束", isOn: model.preferences.viewBinding(\.notifyFinished)); Toggle("自动关闭", isOn: model.preferences.viewBinding(\.notifyAutoClose)); Toggle("异常提醒", isOn: model.preferences.viewBinding(\.notifyAlert))
                                Button("允许系统通知") { Task { model.message = await OriginalNotifications.shared.requestPermission() ? "通知已允许" : "请在系统设置中开启通知" } }
                            }
                        case "消费趋势": Toggle("显示消费趋势", isOn: model.preferences.viewBinding(\.trendEnabled)); Picker("图表", selection: model.preferences.viewBinding(\.trendType)) { Text("折线").tag("LINE"); Text("柱状").tag("BAR") }
                        case "背景装扮": Button("背景装扮") { panel = .background }
                        case "绑定寝室": Text((model.account?.boundRoom ?? "").isEmpty ? "未绑定寝室" : model.account?.boundRoom ?? ""); Button("选择附近") { panel = .room }; if !(model.account?.boundRoom ?? "").isEmpty { Button("取消绑定", role: .destructive) { model.bindRoom("") } }
                        case "账号信息": Text(model.account?.profile.name ?? "趣智校园用户"); if let school = model.account?.profile.schoolName { LabeledContent("学校", value: school) }; if let student = model.account?.profile.studentNumber { LabeledContent("学号", value: student) }; Button("账号管理") { panel = .account }
                        case "使用码":
                            Text(model.account?.useCode.useCode ?? "尚未领取").font(.system(.title2, design: .monospaced)).textSelection(.enabled)
                            Toggle("启用使用码", isOn: Binding(get: { model.account?.useCode.useCodeStatus == 1 }, set: { value in Task { await model.toggleCode(value) } }))
                            Button("领取 / 重新领取") {
                                if model.account?.useCode.resetAvailability == 0 { model.message = model.account?.useCode.resetAvailabilityWarMark ?? "暂不可重新领取" }
                                else { candidateSheet = true; Task { await model.generateCode() } }
                            }
                        case "运行日志": Button("查看运行日志") { panel = .logs }
                        case "软件更新": Button("检查更新") { panel = .updates }
                        default: Button("关于项目") { panel = .about }
                        }
                    }
                }
                Button("编辑卡片布局") { panel = .cards }
                Section("iOS 平台说明") { Text("桌面组件会打开应用执行控制。后台蓝牙由系统调度；强制退出应用后，不能像 Android 前台服务一样保证持续监控或自动关阀。").font(.footnote) }
            }.navigationTitle("设置").toolbar { Button("完成") { dismiss() } }
            .sheet(item: $panel) { item in
                switch item {
                case .background: OriginalBackgroundSettings(model: model)
                case .room: OriginalRoomPicker(model: model)
                case .logs: OriginalLogView(logs: model.logs)
                case .cards: OriginalCardEditor(preferences: model.preferences)
                case .updates: OriginalUpdateView()
                case .account: OriginalAccountManagement(model: model)
                default: OriginalAboutView()
                }
            }
            .sheet(isPresented: $candidateSheet) { OriginalCodeCandidateView(model: model) }
        }
    }
}

@MainActor struct OriginalCardEditor: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("我的页面") {
                    ForEach(preferences.cardOrder, id: \.self) { name in
                        HStack { Toggle(name, isOn: Binding(get: { !preferences.hiddenCards.contains(name) }, set: { if $0 { preferences.hiddenCards.remove(name) } else { preferences.hiddenCards.insert(name) } })); Menu { Button("移到设置") { preferences.cardOrder.removeAll { $0 == name }; if !preferences.settingsOrder.contains(name) { preferences.settingsOrder.append(name) } } } label: { Image(systemName: "ellipsis") } }
                    }.onMove { preferences.cardOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("设置页面") {
                    ForEach(preferences.settingsOrder, id: \.self) { name in
                        HStack { Toggle(name, isOn: Binding(get: { !preferences.hiddenSettings.contains(name) }, set: { if $0 { preferences.hiddenSettings.remove(name) } else { preferences.hiddenSettings.insert(name) } })); Menu { Button("移到我的") { preferences.settingsOrder.removeAll { $0 == name }; if !preferences.cardOrder.contains(name) { preferences.cardOrder.append(name) } } } label: { Image(systemName: "ellipsis") } }
                    }.onMove { preferences.settingsOrder.move(fromOffsets: $0, toOffset: $1) }
                }
            }.environment(\.editMode, .constant(.active)).navigationTitle("卡片布局").toolbar { Button("完成") { dismiss() } }
        }
    }
}

@MainActor struct OriginalBackgroundSettings: View {
    @ObservedObject var model: OriginalAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    var body: some View {
        NavigationStack {
            Form {
                Picker("背景", selection: model.preferences.viewBinding(\.backgroundScope)) { Text("主页").tag("home"); Text("使用页").tag("shower") }.pickerStyle(.segmented)
                OriginalBackground(preferences: model.preferences, shower: model.preferences.backgroundScope == "shower").frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 18))
                PhotosPicker(selection: $photo, matching: .images) { Label("从相册选择背景", systemImage: "photo") }
                LabeledContent("透明度") { Slider(value: model.preferences.viewBinding(\.opacity), in: 0...1) }
                LabeledContent("模糊") { Slider(value: model.preferences.viewBinding(\.blur), in: 0...30) }
                LabeledContent("亮度") { Slider(value: model.preferences.viewBinding(\.brightness), in: 0.4...1.5) }
                Button("恢复默认") { model.preferences.resetBackground(scope: model.preferences.backgroundScope) }
            }.navigationTitle("背景装扮").toolbar { Button("完成") { dismiss() } }
            .onChange(of: photo) { item in
                let scope = model.preferences.backgroundScope
                Task { guard let data = try? await item?.loadTransferable(type: Data.self) else { return }; do { try model.preferences.setBackground(data, scope: scope) } catch { model.report(error) } }
            }
        }
    }
}

@MainActor struct OriginalLogView: View {
    @ObservedObject var logs: OriginalLogs
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { List(logs.entries.indices, id: \.self) { index in Text(logs.entries[index]).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.navigationTitle("运行日志").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .primaryAction) { HStack { if let url = logs.export() { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }; Button("清空") { logs.clear() } } } } }
    }
}

private struct OriginalRelease: Decodable, Identifiable {
    let id: Int
    let tag_name: String
    let body: String?
    let html_url: URL
    let prerelease: Bool
    let draft: Bool
}
@MainActor struct OriginalUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var releases: [OriginalRelease] = []
    @State private var message = ""
    var body: some View {
        NavigationStack {
            List {
                Section { Text("当前：LinYu iOS 移植开发版"); Text("下方为原仓库发布记录。Android APK 不能用于更新 iOS；iOS 安装与更新需使用签名后的分发版本。").font(.footnote).foregroundStyle(.secondary) }
                ForEach(releases.prefix(3)) { release in DisclosureGroup(release.tag_name) { Text(release.body ?? "暂无更新说明").font(.footnote); Link("查看发布页", destination: release.html_url) } }
                if !message.isEmpty { Text(message) }
                Button("重新检查") { Task { await refresh() } }
            }.navigationTitle("软件更新").toolbar { Button("关闭") { dismiss() } }.task { await refresh() }
        }
    }
    private func refresh() async {
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/yehu-imei/linyu/releases?per_page=10")!); request.setValue("LinYu-iOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            releases = try JSONDecoder().decode([OriginalRelease].self, from: data).filter { !$0.prerelease && !$0.draft }; message = releases.isEmpty ? "暂无发布记录" : ""
        } catch { message = "检查失败：\(error.localizedDescription)" }
    }
}
struct OriginalAboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { List { Section("淋浴 LinYu") { Text("趣智校园第三方客户端 · iOS 移植"); Text("以原版功能与业务流程为基准，MIT 许可。"); Link("原项目 yehu-imei/linyu", destination: URL(string: "https://github.com/yehu-imei/linyu")!) }; Section("当前状态") { Text("实现稿尚待 macOS/Xcode 编译、签名和真实设备验证。蓝牙、云端、账户及钱包均未在本次开发中操作真实账号或水表。"); Text("iOS 的后台、桌面组件和安装更新机制与 Android 不同，不能承诺强制退出后继续自动关阀。") } }.navigationTitle("关于项目").toolbar { Button("关闭") { dismiss() } } }
    }
}
