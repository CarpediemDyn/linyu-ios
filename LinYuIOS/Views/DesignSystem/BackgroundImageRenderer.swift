import CoreImage
import MetalKit
import SwiftUI
import UIKit

struct BackgroundEffects: Equatable {
    let opacity: Double
    let blur: Double
    let brightness: Double
    init(_ config: BackgroundConfiguration) {
        opacity = config.opacity; blur = config.blur; brightness = config.brightness
    }
}

/// One rendering path for the preview and the real background. RGB gain is multiplicative,
/// matching Android ColorMatrix; SwiftUI's additive brightness modifier has different semantics.
enum BackgroundRenderPipeline {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Core Image uses a lower-left origin; the displayed Metal drawable uses top-left.
    static func render(_ image: CIImage, to texture: MTLTexture, commandBuffer: MTLCommandBuffer, context: CIContext) throws {
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: commandBuffer)
        destination.colorSpace = colorSpace
        destination.isFlipped = true
        destination.alphaMode = .premultiplied
        _ = try context.startTask(toRender: image, to: destination)
    }

    static func output(_ input: CIImage, size: CGSize, scale: CGFloat, effects: BackgroundEffects) -> CIImage {
        let extent = input.extent
        let gain = max(size.width / extent.width, size.height / extent.height)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: gain, y: gain))
        let positioned = scaled.transformed(by: CGAffineTransform(
            translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX,
            y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY))
        let b = CGFloat(effects.brightness)
        var result = positioned.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(effects.opacity))
        ])
        if effects.blur > 0 {
            result = result.clampedToExtent().applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: effects.blur * Double(scale)])
        }
        return result.cropped(to: CGRect(origin: .zero, size: size))
    }
}

@MainActor private enum BackgroundRenderResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let queue = device?.makeCommandQueue()
    static let colorSpace = BackgroundRenderPipeline.colorSpace
    static let context: CIContext = {
        // Android's ColorMatrix multiplies encoded RGB channels, not linear-light RGB.
        var options: [CIContextOption: Any] = [.cacheIntermediates: false,
            .workingColorSpace: colorSpace, .outputColorSpace: colorSpace]
        if let device { return CIContext(mtlDevice: device, options: options) }
        options[.useSoftwareRenderer] = true
        return CIContext(options: options)
    }()
}

@MainActor struct BackgroundImageRenderer: UIViewRepresentable {
    let image: UIImage
    let effects: BackgroundEffects
    func makeUIView(context: Context) -> BackgroundImageRenderView { BackgroundImageRenderView(frame: .zero) }
    func updateUIView(_ view: BackgroundImageRenderView, context: Context) { view.update(image, effects: effects) }
    static func dismantleUIView(_ view: BackgroundImageRenderView, coordinator: ()) { view.stop() }
}

@MainActor final class BackgroundImageRenderView: UIView, @preconcurrency MTKViewDelegate {
    private var metal: MTKView?
    private var sourceImage: UIImage?
    private var input: CIImage?
    private var effects = BackgroundEffects(BackgroundConfiguration())

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
        if let device = BackgroundRenderResources.device, BackgroundRenderResources.queue != nil {
            let view = MTKView(frame: bounds, device: device)
            view.isOpaque = false
            view.backgroundColor = .clear
            view.framebufferOnly = false
            view.colorPixelFormat = .bgra8Unorm
            (view.layer as? CAMetalLayer)?.colorspace = BackgroundRenderResources.colorSpace
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.clearColor = MTLClearColorMake(0, 0, 0, 0)
            view.delegate = self
            addSubview(view)
            metal = view
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ image: UIImage, effects: BackgroundEffects) {
        guard sourceImage !== image || self.effects != effects else { return }
        if sourceImage !== image {
            sourceImage = image
            input = image.cgImage.map { CIImage(cgImage: $0) }
        }
        self.effects = effects
        redraw()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal?.frame = bounds
        redraw()
    }

    private func redraw() {
        if let metal { metal.setNeedsDisplay() } else { setNeedsDisplay() }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let input, view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable, let buffer = BackgroundRenderResources.queue?.makeCommandBuffer() else { return }
        let output = BackgroundRenderPipeline.output(input, size: view.drawableSize,
            scale: view.contentScaleFactor, effects: effects)
        do {
            try BackgroundRenderPipeline.render(output, to: drawable.texture, commandBuffer: buffer,
                context: BackgroundRenderResources.context)
        } catch {
            // A failed GPU setup must not leave a blank, permanently stale background.
            metal?.delegate = nil
            metal?.removeFromSuperview()
            metal = nil
            OriginalLogs.shared.add("BACKGROUND renderer_fallback")
            setNeedsDisplay()
            return
        }
        buffer.present(drawable)
        buffer.commit()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard metal == nil, let input, bounds.width > 0, bounds.height > 0 else { return }
        let size = CGSize(width: bounds.width * contentScaleFactor, height: bounds.height * contentScaleFactor)
        let output = BackgroundRenderPipeline.output(input, size: size, scale: contentScaleFactor, effects: effects)
        if let cg = BackgroundRenderResources.context.createCGImage(output, from: output.extent) {
            UIImage(cgImage: cg).draw(in: bounds)
        }
    }

    func stop() {
        metal?.delegate = nil
        sourceImage = nil
        input = nil
    }
}

/// Image identity excludes effect values: dragging sliders never restarts decoding.
@MainActor struct BackgroundCanvas: View {
    @ObservedObject var preferences: OriginalPreferences
    let scope: BackgroundScope
    var isPreview = false
    @Environment(\.linYuColors) private var colors
    @State private var image: UIImage?
    @State private var displayedScope: BackgroundScope?
    @State private var loading = false
    @State private var failed = false

    private struct Identity: Equatable {
        let scope: BackgroundScope
        let file: String
        let revision: UUID
        let enabled: Bool
    }

    var body: some View {
        let config = preferences.configuration(for: scope)
        let identity = Identity(scope: scope, file: config.imageFile, revision: config.imageVersion, enabled: config.enabled)
        ZStack {
            colors.background
            if let image, displayedScope == scope, config.enabled {
                BackgroundImageRenderer(image: image, effects: BackgroundEffects(config))
                    .accessibilityHidden(true)
                if isPreview {
                    GeometryReader { geometry in
                        OriginalGlassCard(padding: 14, cornerRadius: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("示例卡片").font(LinYuType.font(14, weight: .semibold)).foregroundStyle(colors.textPrimary)
                                Text("文字在背景上的可读性效果").font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                            }
                        }
                        .padding(16).frame(width: geometry.size.width * 0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else if !config.enabled, isPreview {
                Text("未设置背景").font(LinYuType.font(16)).foregroundStyle(colors.textSecondary)
            } else if failed {
                Text("图片无法读取，请重新选择").font(LinYuType.font(13)).foregroundStyle(colors.textSecondary)
            } else if loading {
                ProgressView().tint(colors.accent)
            }
        }
        .task(id: identity) {
            guard let url = preferences.backgroundURL(for: scope) else {
                image = nil; displayedScope = nil; loading = false; failed = false
                return
            }
            if displayedScope != scope { image = nil }
            loading = true; failed = false
            let value = await preferences.backgroundImages.image(at: url)
            guard !Task.isCancelled else { return }
            image = value; displayedScope = scope; loading = false; failed = value == nil
        }
    }
}
