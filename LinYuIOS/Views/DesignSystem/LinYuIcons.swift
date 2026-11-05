import SwiftUI

/// Original VectorDrawable paths converted to SVG without changing their geometry.
struct LinYuIcon: View {
    let name: String
    var size: CGFloat = 24
    var body: some View {
        Image("Android_" + name).renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct LinYuDeviceGlyph: View {
    let emoji: String
    var size: CGFloat = 24
    var body: some View {
        Group {
            switch emoji {
            case "🚿": LinYuIcon(name: "ic_device_shower", size: size)
            case "🪥": LinYuIcon(name: "ic_device_sink", size: size)
            default: Text(emoji).font(LinYuType.font(size))
            }
        }
    }
}
