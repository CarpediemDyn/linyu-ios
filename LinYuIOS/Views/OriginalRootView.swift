import SwiftUI

@MainActor struct OriginalRootView: View {
    @StateObject private var model = OriginalAppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var direction = 1
    @State private var scanner = false
    @State private var inSettings = false
    @State private var opening = false
    @State private var sessionNotice = false
    private var showingShower: Bool { model.showShower != nil || model.showCloudShower != nil }
    private enum Dialog { case session, automatic, opening, retry, failure, device }
    private var dialog: Dialog? {
        if sessionNotice { return .session }
        if model.automaticFinish != nil { return .automatic }
        if opening { return .opening }
        if model.pendingBluetoothFallback != nil { return .retry }
        if model.startFailure != nil { return .failure }
        if model.selectedDevice != nil { return .device }
        return nil
    }
    private var canDismissDialog: Bool { dialog != .session && dialog != .opening && dialog != .automatic && !model.isBusy }
    private var tab: Binding<Int> {
        Binding(get: { page }, set: { next in
            direction = next > page ? 1 : -1
            inSettings = false
            page = next
        })
    }
    var body: some View {
        LinYuThemeHost(preferences: model.preferences) {
            ZStack(alignment: .bottom) {
                OriginalBackground(preferences: model.preferences, shower: false)
                if model.auth.session == nil {
                    AccountView(auth: model.auth)
                } else {
                    pages.opacity(showingShower ? 0 : 1).allowsHitTesting(!showingShower).accessibilityHidden(showingShower)
                    if showingShower {
                        OriginalShowerView(model: model, onBack: closeShowerPage)
                            .transition(.opacity)
                    } else if !inSettings {
                        LinYuPillNavigation(selection: tab).padding(.bottom, 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                OriginalToast(message: model.message) { text in
                    if model.message == text { model.message = "" }
                }
            }
            .linYuModal(isPresented: Binding(get: { dialog != nil }, set: { visible in if !visible { dismissDialog() } }),
                        canDismiss: canDismissDialog) { dialogContent }
            .fullScreenCover(isPresented: $scanner) {
                OriginalScannerView { code in Task { await model.scanCode(code) } }
            }
            .animation(.easeInOut(duration: 0.2), value: showingShower)
        }
        .onAppear { model.setForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { model.setForeground($0 == .active) }
        .onChange(of: model.auth.session?.ownerScope) { owner in
            if owner != nil { page = 0; inSettings = false; sessionNotice = false }
            else if model.auth.activity.contains("登录状态已失效") { sessionNotice = true }
        }
        .onOpenURL { url in Task { await model.handle(url) } }
    }
    private var pages: some View {
        Group {
            switch page {
            case 1: OriginalWalletView(model: model, onModalVisibilityChanged: { inSettings = $0 })
            case 2: OriginalProfileView(model: model)
            default: OriginalHomeView(model: model, onScan: { scanner = true }, onStart: start)
            }
        }
        .id(page).frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)))
        .animation(.interpolatingSpring(stiffness: 420, damping: 32), value: page)
        .clipped()
    }
    @ViewBuilder private var dialogContent: some View {
        switch dialog {
        case .session:
            LinYuDialogCard {
                VStack(spacing: 24) {
                    Text("登录状态已失效").font(LinYuType.font(24, weight: .bold))
                    Text("当前登录已失效。设备可能仍在用水，请重新登录核对，或立即使用官方客户端、联系人工处理。")
                        .multilineTextAlignment(.center)
                    Button { sessionNotice = false } label: { Text("确定").frame(maxWidth: .infinity) }.buttonStyle(LinYuButtonStyle())
                }.frame(maxWidth: .infinity)
            }
        case .automatic:
            if let event = model.automaticFinish {
                OriginalAutomaticCloseDialog(event: event) { model.automaticFinish = nil }
            }
        case .opening: OriginalStartingDeviceDialog()
        case .retry:
            if let device = model.pendingBluetoothFallback {
                OriginalBluetoothRetryDialog(device: device, onConfirm: {
                    guard !model.isBusy else { return }
                    model.pendingBluetoothFallback = nil
                    model.setBluetooth(true, device: device)
                    start(device)
                }, onDismiss: { model.pendingBluetoothFallback = nil })
            }
        case .failure:
            if let failure = model.startFailure {
                OriginalStartFailureView(model: model, failure: failure) { model.startFailure = nil }
            }
        case .device:
            if let device = model.selectedDevice {
                OriginalDeviceDetail(model: model, device: device, onStart: start) { model.selectedDevice = nil }
            }
        case nil: EmptyView()
        }
    }
    private func dismissDialog() {
        guard canDismissDialog else { return }
        switch dialog {
        case .retry: model.pendingBluetoothFallback = nil
        case .failure: model.startFailure = nil
        case .device: model.selectedDevice = nil
        default: break
        }
    }
    private func closeShowerPage() { model.showShower = nil; model.showCloudShower = nil }
    private func start(_ device: CampusDevice) {
        guard !opening, !model.isBusy else { return }
        opening = true
        Task { await model.start(device); opening = false }
    }
}

struct OriginalToast: View {
    let message: String
    let onFinish: (String) -> Void
    @State private var visible = false
    var body: some View {
        Group {
            if visible && !message.isEmpty {
                HStack(spacing: 12) {
                    Image("OriginalLogo").resizable().frame(width: 32, height: 32)
                    LinYuTailText(text: message, size: 14, weight: .medium).foregroundStyle(.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color(linYuHex: 0x1F2937), in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                .padding(.horizontal, 24).padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }.allowsHitTesting(false)
            .task(id: message) {
                let text = message
                withAnimation(.easeOut(duration: 0.25)) { visible = !text.isEmpty }
                guard !text.isEmpty else { return }
                do {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeIn(duration: 0.3)) { visible = false }
                    try await Task.sleep(nanoseconds: 300_000_000)
                    onFinish(text)
                } catch {}
            }
    }
}
