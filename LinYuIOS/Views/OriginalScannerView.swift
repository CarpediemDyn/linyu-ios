import SwiftUI
import AVFoundation
import PhotosUI
import Vision

@MainActor struct OriginalScannerView: View {
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var torch = false
    @State private var photo: PhotosPickerItem?
    @State private var message = "将水表二维码放入框内"
    @State private var hasResult = false
    var body: some View {
        ZStack {
            ScannerCamera(torch: torch, onCode: match, onError: { message = $0 }).ignoresSafeArea()
            VStack {
                HStack { Button("返回") { dismiss() }; Spacer(); Text("扫一扫").font(.headline); Spacer() }.padding()
                Spacer()
                RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 260, height: 260)
                Text(message).font(.subheadline).padding().background(.ultraThinMaterial, in: Capsule())
                Spacer()
                HStack(spacing: 70) {
                    Button { torch.toggle() } label: { Label("手电筒", systemImage: torch ? "flashlight.on.fill" : "flashlight.off.fill") }
                    PhotosPicker(selection: $photo, matching: .images) { Label("相册", systemImage: "photo") }
                }.padding(32)
            }.foregroundStyle(.white)
        }.background(.black)
        .onChange(of: photo) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                let values: [String] = await Task.detached {
                    let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
                    try? VNImageRequestHandler(data: data, options: [:]).perform([request])
                    return request.results?.compactMap(\.payloadStringValue) ?? []
                }.value
                if let value = values.first(where: { OriginalFormatting.parseDeviceQR($0) != nil }) { match(value) }
                else { message = "这张图片里没有找到设备二维码" }
            }
        }
    }
    private func match(_ raw: String) {
        guard !hasResult, let code = OriginalFormatting.parseDeviceQR(raw) else { return }
        hasResult = true
        torch = false; dismiss(); onFound(code)
    }
}

private struct ScannerCamera: UIViewRepresentable {
    let torch: Bool
    let onCode: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }
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
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onCode = onCode; self.onError = onError }
        func start() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self else { return }
                guard allowed else { DispatchQueue.main.async { self.onError("请在系统设置中允许相机权限") }; return }
                self.queue.async {
                    do {
                        guard !self.finished, let camera = AVCaptureDevice.default(for: .video) else { return }
                        self.session.beginConfiguration(); defer { self.session.commitConfiguration() }
                        let input = try AVCaptureDeviceInput(device: camera)
                        guard self.session.canAddInput(input) else { return }
                        self.session.addInput(input)
                        let output = AVCaptureMetadataOutput()
                        guard self.session.canAddOutput(output) else { return }
                        self.session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
                        output.metadataObjectTypes = [.qr]; self.device = camera
                        self.queue.async { if !self.finished { self.session.startRunning() } }
                    } catch { DispatchQueue.main.async { self.onError("相机启动失败，请尝试相册识别") } }
                }
            }
        }
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
