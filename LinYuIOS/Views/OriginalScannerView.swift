import SwiftUI
import AVFoundation
import PhotosUI
import Vision
import UIKit

@MainActor struct OriginalScannerView: View {
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var torch = false
    @State private var photo: PhotosPickerItem?
    @State private var hint: String?
    @State private var hasResult = false
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var denied = false
    @State private var cameraFailed = false
    @State private var hasTorch = false
    @State private var cameraGeneration = UUID()
    @Environment(\.scenePhase) private var scenePhase
    private let yellow = Color(linYuHex: 0xFFC53D)
    private var cameraLive: Bool { authorization == .authorized && !cameraFailed }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if cameraLive {
                    ScannerCamera(torch: torch, onCode: match, onError: { _ in cameraFailed = true }, onReady: { hasTorch = $0 })
                        .id(cameraGeneration).ignoresSafeArea()
                    VStack(spacing: 0) {
                        header.padding(.top, 4)
                        GeometryReader { space in
                            OriginalScannerOverlay(size: space.size)
                        }
                        controls(compact: geometry.size.height < 460)
                            .padding(.bottom, geometry.size.height < 460 ? 6 : 24)
                    }
                    .frame(maxWidth: 620)
                } else {
                    ScrollView {
                        notice.frame(minHeight: geometry.size.height)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.background(.black).preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onChange(of: photo) { item in
            Task {
                guard let item else { return }
                guard let data = try? await item.loadTransferable(type: Data.self) else { hint = "这张图片读不出来，换一张试试"; return }
                let values: [String] = await Task.detached {
                    let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
                    do { try VNImageRequestHandler(data: data, options: [:]).perform([request]) }
                    catch { return ["__image_recognition_failed__"] }
                    return request.results?.compactMap(\.payloadStringValue) ?? []
                }.value
                if values == ["__image_recognition_failed__"] { hint = "图片识别失败，换一张试试"; return }
                if let value = values.first(where: { OriginalFormatting.parseDeviceQR($0) != nil }) { match(value) }
                else { hint = "这张图片里没有找到设备二维码" }
            }
        }
        .task(id: hint) {
            guard let current = hint else { return }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled, hint == current else { return }; hint = nil
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { authorization = AVCaptureDevice.authorizationStatus(for: .video) }
        }
        .onDisappear { torch = false }
        .accessibilityIdentifier("linyu.scanner")
    }
    private var header: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: { LinYuIcon(name: "arrow_back").frame(width: 48, height: 48) }.buttonStyle(.plain).accessibilityLabel("返回")
            Text("扫描二维码").font(LinYuType.font(17, weight: .medium))
            Spacer()
        }.foregroundStyle(.white).padding(.horizontal, 4)
    }
    private func controls(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 18) {
            Text(hint ?? "将二维码放入框内，自动扫描").font(LinYuType.font(13))
                .foregroundStyle(hint == nil ? Color.white.opacity(0.75) : yellow)
                .multilineTextAlignment(.center).padding(.horizontal, 12)
            HStack {
                Spacer()
                PhotosPicker(selection: $photo, matching: .images) { OriginalScanCircle(icon: "ic_photo_library") }.accessibilityLabel("从相册选择")
                Spacer()
                if hasTorch {
                    Button { torch.toggle() } label: { OriginalScanCircle(icon: torch ? "ic_flashlight_on" : "ic_flashlight", lit: torch) }
                        .buttonStyle(.plain).accessibilityLabel(torch ? "关闭手电筒" : "打开手电筒")
                } else { Color.clear.frame(width: 52, height: 52) }
                Spacer()
                Button { dismiss() } label: { OriginalScanCircle(icon: "ic_qr_code_scanner") }.buttonStyle(.plain).accessibilityLabel("取消扫码")
                Spacer()
            }
        }
    }
    private var notice: some View {
        VStack(spacing: 0) {
            Text(authorization != .authorized ? "需要相机权限" : "相机启动失败").font(LinYuType.font(18, weight: .bold)).foregroundStyle(.white)
            Text(noticeDescription).font(LinYuType.font(13)).foregroundStyle(.white.opacity(0.65)).padding(.top, 10)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { noticeActions }
                VStack(spacing: 4) { noticeActions }
            }.buttonStyle(.plain).font(LinYuType.font(14)).foregroundStyle(yellow).padding(.top, 12)
        }.padding(.horizontal, 16).frame(maxWidth: 520)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    @ViewBuilder private var noticeActions: some View {
                if authorization != .authorized {
                    Button(action: requestPermission) { Text("授予权限").frame(minHeight: 44) }
                    if denied || authorization == .denied || authorization == .restricted {
                        Button("去设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                } else {
                    Button { cameraFailed = false; cameraGeneration = UUID() } label: { Text("重试").frame(minHeight: 44) }
                }
                Button { dismiss() } label: { Text("返回").frame(minWidth: 44, minHeight: 44) }
    }
    private var noticeDescription: String {
        if authorization == .authorized { return "可能是相机被其他应用占用，或者设备不支持。稍后再试一次，或者重启一下手机" }
        if denied || authorization == .denied || authorization == .restricted { return "权限被拒绝了。可以点下面的「授予权限」再试一次，或者去系统设置里打开" }
        return "扫码要用到相机。权限只用于识别二维码，不会拍照上传"
    }
    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            Task { @MainActor in
                authorization = AVCaptureDevice.authorizationStatus(for: .video); denied = !allowed
                if !allowed { hint = "没有相机权限就没法扫码" }
            }
        }
    }
    private func match(_ raw: String) {
        guard !hasResult, let code = OriginalFormatting.parseDeviceQR(raw) else { return }
        hasResult = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        torch = false; dismiss(); onFound(code)
    }
}

private struct OriginalScanCircle: View {
    let icon: String
    var lit = false
    private let yellow = Color(linYuHex: 0xFFC53D)
    var body: some View {
        LinYuIcon(name: icon, size: 22).foregroundStyle(lit ? Color(linYuHex: 0x1A1206) : .white)
            .frame(width: 52, height: 52).background(lit ? yellow : Color.white.opacity(0.10), in: Circle())
            .overlay(Circle().stroke(lit ? .clear : Color.white.opacity(0.28), lineWidth: 1))
            .background { if lit { Circle().fill(yellow.opacity(0.22)).frame(width: 64, height: 64) } }
    }
}

struct OriginalScannerOverlay: View {
    let size: CGSize
    @State private var progress: CGFloat = 0
    private var side: CGFloat { max(0, min(size.width * 0.72, size.height * 0.9, 280)) }
    private var left: CGFloat { (size.width - side) / 2 }
    private var top: CGFloat { (size.height - side) / 2 }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let rects = [CGRect(x: 0, y: 0, width: size.width, height: top),
                             CGRect(x: 0, y: top + side, width: size.width, height: max(0, size.height - top - side)),
                             CGRect(x: 0, y: top, width: left, height: side),
                             CGRect(x: left + side, y: top, width: left, height: side)]
                for rect in rects { context.fill(Path(rect), with: .color(.black.opacity(0.62))) }
                let corner = side * 0.16
                let right = left + side; let bottom = top + side
                var path = Path()
                path.move(to: CGPoint(x: left, y: top + corner)); path.addLine(to: CGPoint(x: left, y: top)); path.addLine(to: CGPoint(x: left + corner, y: top))
                path.move(to: CGPoint(x: right - corner, y: top)); path.addLine(to: CGPoint(x: right, y: top)); path.addLine(to: CGPoint(x: right, y: top + corner))
                path.move(to: CGPoint(x: right, y: bottom - corner)); path.addLine(to: CGPoint(x: right, y: bottom)); path.addLine(to: CGPoint(x: right - corner, y: bottom))
                path.move(to: CGPoint(x: left + corner, y: bottom)); path.addLine(to: CGPoint(x: left, y: bottom)); path.addLine(to: CGPoint(x: left, y: bottom - corner))
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            Rectangle().fill(LinearGradient(colors: [.clear, Color(linYuHex: 0xFFC53D).opacity(0.85), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: max(0, side - 8), height: 14).offset(x: left + 4, y: top + side * progress - 7)
        }.allowsHitTesting(false).accessibilityHidden(true)
            .onAppear { withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: true)) { progress = 1 } }
    }
}

private struct ScannerCamera: UIViewRepresentable {
    let torch: Bool
    let onCode: (String) -> Void
    let onError: (String) -> Void
    let onReady: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError, onReady: onReady) }
    func makeUIView(context: Context) -> ScannerPreview {
        let view = ScannerPreview(); view.preview.session = context.coordinator.session
        view.preview.videoGravity = .resizeAspectFill; context.coordinator.start(); return view
    }
    func updateUIView(_ view: ScannerPreview, context: Context) { context.coordinator.setTorch(torch) }
    static func dismantleUIView(_ view: ScannerPreview, coordinator: Coordinator) { coordinator.stop() }
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "linyu.camera")
        private var device: AVCaptureDevice?
        private var finished = false
        let onCode: (String) -> Void
        let onError: (String) -> Void
        let onReady: (Bool) -> Void
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void, onReady: @escaping (Bool) -> Void) { self.onCode = onCode; self.onError = onError; self.onReady = onReady }
        func start() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self else { return }
                guard allowed else { DispatchQueue.main.async { self.onError("请在系统设置中允许相机权限") }; return }
                self.queue.async {
                    do {
                        guard !self.finished else { return }
                        guard let camera = AVCaptureDevice.default(for: .video) else { self.fail(); return }
                        self.session.beginConfiguration(); defer { self.session.commitConfiguration() }
                        let input = try AVCaptureDeviceInput(device: camera)
                        guard self.session.canAddInput(input) else { self.fail(); return }
                        self.session.addInput(input)
                        let output = AVCaptureMetadataOutput()
                        guard self.session.canAddOutput(output) else { self.fail(); return }
                        self.session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
                        output.metadataObjectTypes = [.qr]; self.device = camera
                        DispatchQueue.main.async { self.onReady(camera.hasTorch) }
                        self.queue.async { if !self.finished { self.session.startRunning() } }
                    } catch { DispatchQueue.main.async { self.onError("相机启动失败，请尝试相册识别") } }
                }
            }
        }
        private func fail() { DispatchQueue.main.async { self.onError("相机启动失败") } }
        func setTorch(_ on: Bool) {
            queue.async { guard let d = self.device, d.hasTorch else { return }; do { try d.lockForConfiguration(); d.torchMode = on ? .on : .off; d.unlockForConfiguration() } catch {} }
        }
        func stop() { queue.async { self.finished = true; self.session.stopRunning(); if let d = self.device, d.hasTorch { do { try d.lockForConfiguration(); d.torchMode = .off; d.unlockForConfiguration() } catch {} } } }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first(where: { $0.range(of: "KLCXKJ-Water", options: .caseInsensitive) != nil }) else { return }
            onCode(value)
        }
    }
}
private final class ScannerPreview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
