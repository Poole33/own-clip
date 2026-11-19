import AppKit
import SwiftUI

struct ToolbarGlass<S: Shape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content
        }
    }
}

struct ToolbarGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) { content }
        } else {
            content
        }
    }
}

private struct LegacyPanelDragHandle: NSViewRepresentable {
    final class DragView: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView(frame: .zero)
        view.isBordered = false
        view.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        view.contentTintColor = .secondaryLabelColor
        return view
    }
    func updateNSView(_ view: DragView, context: Context) {}
}

struct PanelDragHandle: View {
    let help: String

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            } else {
                LegacyPanelDragHandle()
            }
        }
        .frame(width: 23, height: 30)
        .help(help)
        .accessibilityHidden(true)
    }
}

struct IconControl: View {
    let symbol: String
    let label: String
    var foregroundColor: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 27, height: 27)
                .modifier(ToolbarGlass(shape: Circle(), interactive: true))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor ?? PanelStyle.secondaryText)
        .accessibilityLabel(label)
        .help(label)
    }
}

