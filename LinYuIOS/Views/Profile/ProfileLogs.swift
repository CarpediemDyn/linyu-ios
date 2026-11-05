import SwiftUI
import UIKit

@MainActor struct ProfileLogDialog: View {
    private struct Export: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @ObservedObject var logs: OriginalLogs
    let onClose: () -> Void
    @Environment(\.linYuColors) private var colors
    @State private var snapshot: [String]?
    @State private var share: Export?

    private var entries: [String] { snapshot ?? logs.entries }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("运行日志 (\(entries.count))").font(LinYuType.font(16, weight: .bold))
                        .foregroundStyle(colors.textPrimary).accessibilityAddTraits(.isHeader)
                    Spacer()
                    ProfileIconAction("close", label: "关闭", color: colors.textSecondary, action: onClose)
                }
                .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 12)
                ProfileDivider()
                if entries.isEmpty {
                    Text("暂无日志").font(LinYuType.font(16)).foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProfileLogScroll(entries: entries.map(redacted), textColor: UIColor(colors.textPrimary),
                                     thumbColor: UIColor(colors.textSecondary.opacity(0.45)))
                }
                ProfileDivider()
                HStack(spacing: 12) {
                    Button {
                        logs.clear()
                        snapshot = []
                    } label: {
                        Text("清空").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LinYuOutlinedButtonStyle(cornerRadius: 12))
                    Button(action: export) {
                        Text("导出/分享").foregroundStyle(.white).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LinYuButtonStyle(color: colors.accent, cornerRadius: 12))
                }
                .padding(16)
            }
            .frame(maxWidth: 560)
            .frame(height: geometry.size.height * 0.85)
            .background(colors.solidSurface, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { if snapshot == nil { snapshot = logs.entries } }
        .sheet(item: $share) { export in
            ProfileLogShare(url: export.url)
        }
    }

    private func export() {
        let fileLines = logs.export().flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.split(separator: "\n", omittingEmptySubsequences: true).suffix(500).map(String.init) } ?? []
        let lines = fileLines.isEmpty ? logs.entries : fileLines
        guard !lines.isEmpty else {
            logs.add("没有可导出的日志")
            return
        }
        let time = Int64(Date().timeIntervalSince1970 * 1000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("linyu_log_\(time).txt")
        do {
            try lines.map(redacted).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            share = Export(url: url)
        } catch {
            logs.add("导出日志失败：\(error.localizedDescription)")
        }
    }

    private func redacted(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"(?i)(password|loginCode|secret|telPhone|telephone|smsCode|useCode|userId|accountId|(?<![A-Za-z])code)["']?\s*[:=]\s*["']?([^"'&\s,}]+)"#,
            with: "$1=***", options: .regularExpression
        )
    }
}

private struct ProfileLogShare: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ProfileLogScroll: UIViewRepresentable {
    let entries: [String]
    let textColor: UIColor
    let thumbColor: UIColor

    func makeUIView(context: Context) -> LogScrollContainer { LogScrollContainer(frame: .zero) }

    func updateUIView(_ view: LogScrollContainer, context: Context) {
        view.apply(entries: entries, textColor: textColor, thumbColor: thumbColor)
    }

    final class LogScrollContainer: UIView, UITextViewDelegate {
        private let textView = UITextView()
        private let thumbTarget = UIView()
        private let thumb = UIView()
        private let thumbHeight: CGFloat = 40
        private let edgePadding: CGFloat = 8
        private var lastEntries: [String] = []
        private var lastColor: UIColor?

        override init(frame: CGRect) {
            super.init(frame: frame)
            textView.backgroundColor = .clear
            textView.isEditable = false
            textView.isSelectable = false
            textView.showsVerticalScrollIndicator = false
            textView.textContainerInset = UIEdgeInsets(top: edgePadding, left: 14, bottom: edgePadding, right: 14)
            textView.textContainer.lineFragmentPadding = 0
            textView.delegate = self
            addSubview(textView)
            thumb.layer.cornerRadius = 2
            thumbTarget.addSubview(thumb)
            thumbTarget.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragThumb(_:))))
            addSubview(thumbTarget)
        }

        required init?(coder: NSCoder) { nil }

        func apply(entries: [String], textColor: UIColor, thumbColor: UIColor) {
            thumb.backgroundColor = thumbColor
            guard entries != lastEntries || lastColor != textColor else { return }
            let oldOffset = textView.contentOffset
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            textView.attributedText = NSAttributedString(string: entries.joined(separator: "\n"), attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ])
            if lastEntries == entries { textView.setContentOffset(oldOffset, animated: false) }
            lastEntries = entries
            lastColor = textColor
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            textView.frame = bounds
            updateThumb()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { updateThumb() }

        private var travel: CGFloat { max(0, bounds.height - edgePadding * 2 - thumbHeight) }
        private var scrollRange: CGFloat { max(0, textView.contentSize.height - textView.bounds.height) }

        private func updateThumb() {
            let progress = scrollRange > 0 ? min(1, max(0, textView.contentOffset.y / scrollRange)) : 0
            thumbTarget.frame = CGRect(x: bounds.width - 20, y: edgePadding + travel * progress,
                                       width: 20, height: thumbHeight)
            thumb.frame = CGRect(x: 16, y: 0, width: 4, height: thumbHeight)
        }

        @objc private func dragThumb(_ gesture: UIPanGestureRecognizer) {
            guard travel > 0 else { return }
            let delta = gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            let offset = min(scrollRange, max(0, textView.contentOffset.y + delta / travel * scrollRange))
            textView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }
    }
}
