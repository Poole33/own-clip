import AppKit
import SwiftUI

// Shared by horizontal history, vertical history and sequential paste.
enum PanelStyle {
    static let material: NSVisualEffectView.Material = .popover
    static var opaqueBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var selectionBackground: Color { Color(nsColor: .selectedContentBackgroundColor) }
    static var selectionText: Color { Color(nsColor: .alternateSelectedControlTextColor) }
    static var cardBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var primaryText: Color { Color(nsColor: .labelColor) }
    static var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }

    static func background(isSelected: Bool, isCard: Bool = false) -> Color {
        isSelected ? selectionBackground : (isCard ? cardBackground : .clear)
    }

    static func text(isSelected: Bool, secondary: Bool = false) -> Color {
        isSelected ? selectionText : (secondary ? secondaryText : primaryText)
    }
}

private struct NativePanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = PanelStyle.material
        view.blendingMode = .behindWindow
        // Nonactivating panels should retain their material while another app is active.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = PanelStyle.material
    }
}

struct PanelBackground: ViewModifier {
    var fullWidth = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder private var material: some View {
        if reduceTransparency { PanelStyle.opaqueBackground }
        else { NativePanelMaterial().allowsHitTesting(false) }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if fullWidth {
            content
                .background { material }
        } else {
            content
                .background { material }
                .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(.primary.opacity(0.12)).allowsHitTesting(false) }
                .clipShape(RoundedRectangle(cornerRadius: 17))
        }
    }
}

