import SwiftUI
import UIKit
import QuartzCore

/// CircularRevealTheme.kt uses this curve for both mask opacity and circle radius.
enum LinYuRevealTiming {
    static let duration: CFTimeInterval = 0.65
    static let previewProgress = 0.2

    static func easedProgress(elapsed: CFTimeInterval) -> Double {
        let time = min(1, max(0, elapsed / duration))
        if time == 0 || time == 1 { return time }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<20 {
            let t = (lower + upper) / 2
            let u = 1 - t
            let x = 1.2 * u * u * t + 0.6 * u * t * t + t * t * t
            if x < time { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return t * t * (3 - 2 * t)
    }
}

struct LinYuRevealFrame {
    let progress: Double
    let origin: CGPoint

    var alpha: CGFloat { CGFloat(min(1, max(0, progress / LinYuRevealTiming.previewProgress))) }

    func center(in size: CGSize) -> CGPoint {
        origin == .zero ? CGPoint(x: max(0, size.width - 36), y: 48) : origin
    }

    func circle(in size: CGSize) -> CGRect {
        let center = center(in: size)
        let maxRadius = max(max(hypot(center.x, center.y), hypot(size.width - center.x, center.y)),
                            max(hypot(center.x, size.height - center.y),
                                hypot(size.width - center.x, size.height - center.y))) * 1.15
        let fraction = min(1, max(0, (progress - LinYuRevealTiming.previewProgress) / 0.8))
        let radius = maxRadius * CGFloat(fraction)
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// No application state is published on display-link ticks. SwiftUI is notified only at
/// the preview threshold and completion, matching Compose's draw-phase progress reads.
@MainActor struct LinYuRevealDrawing: UIViewRepresentable {
    let origin: CGPoint
    let oldColor: UIColor
    let previewApplied: Bool
    let onPreview: () -> Void
    let onCompletion: () -> Void

    func makeUIView(context: Context) -> LinYuRevealMaskView {
        let view = LinYuRevealMaskView(frame: .zero)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: LinYuRevealMaskView, context: Context) {
        view.origin = origin
        view.oldColor = oldColor
        view.previewApplied = previewApplied
        view.onPreview = onPreview
        view.onCompletion = onCompletion
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: LinYuRevealMaskView, coordinator: ()) { view.stop() }
}

@MainActor final class LinYuRevealMaskView: UIView {
    var origin = CGPoint.zero
    var oldColor = UIColor.clear
    var previewApplied = false
    var onPreview: (() -> Void)?
    var onCompletion: (() -> Void)?
    private(set) var progress = 0.0
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval?
    private var firstFrameDrawn = false
    private var previewRequested = false
    private var completed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
        // The renderer clears transparent pixels before each expanding circle is drawn.
        clearsContextBeforeDrawing = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
        else if displayLink == nil, !completed {
            let link = CADisplayLink(target: LinYuRevealDisplayLinkTarget(view: self), selector: #selector(LinYuRevealDisplayLinkTarget.tick(_:)))
            // Use the display cadence and its power-saving policy.
            link.add(to: .main, forMode: .common)
            displayLink = link
            setNeedsDisplay()
        }
    }

    func advance(at timestamp: CFTimeInterval) {
        guard firstFrameDrawn, !completed else { return }
        guard let startedAt else {
            self.startedAt = timestamp
            return
        }
        let eased = LinYuRevealTiming.easedProgress(elapsed: timestamp - startedAt)
        if eased >= LinYuRevealTiming.previewProgress, !previewApplied {
            // Keep an opaque mask with a zero-radius hole until SwiftUI has applied the
            // palette and system style. A delayed main-thread commit cannot reveal old UI.
            progress = LinYuRevealTiming.previewProgress
            setNeedsDisplay()
            if !previewRequested {
                previewRequested = true
                onPreview?()
            }
            return
        }
        progress = eased
        setNeedsDisplay()
        if eased == 1 {
            completed = true
            stop()
            onCompletion?()
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        Self.draw(LinYuRevealFrame(progress: progress, origin: origin), color: oldColor, in: bounds)
        firstFrameDrawn = true
    }

    /// Shared by the live mask and deterministic raster tests, including safe-area edges.
    static func draw(_ frame: LinYuRevealFrame, color: UIColor, in bounds: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        context.addRect(bounds)
        let circle = frame.circle(in: bounds.size).offsetBy(dx: bounds.minX, dy: bounds.minY)
        if circle.width > 0 { context.addEllipse(in: circle) }
        context.clip(using: .evenOdd)
        context.setFillColor(color.withAlphaComponent(frame.alpha).cgColor)
        context.fill(bounds)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit { displayLink?.invalidate() }
}

/// CADisplayLink retains its target. This weak bridge lets the overlay deallocate on removal.
@MainActor private final class LinYuRevealDisplayLinkTarget: NSObject {
    weak var view: LinYuRevealMaskView?
    init(view: LinYuRevealMaskView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.advance(at: link.timestamp) }
}
