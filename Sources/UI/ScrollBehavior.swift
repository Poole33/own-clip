import AppKit
import SwiftUI

struct HistoryWheel {
    static func horizontalDistance(for event: NSEvent) -> CGFloat? {
        let modifiers = event.modifierFlags
        guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              modifiers.intersection([.control, .option, .command]).isEmpty else { return nil }

        let hasGesturePhase = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        guard !hasGesturePhase || modifiers.contains(.shift) else { return nil }

        // AppKit reports precise deltas in points and conventional wheel deltas in lines.
        return event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 48)
    }
}

struct NativeScrollBehavior: NSViewRepresentable {
    enum Mode {
        case horizontalHistory
        case verticalIndicators
    }

    let mode: Mode

    func makeNSView(context: Context) -> ScrollAttachment { ScrollAttachment(mode: mode) }
    func updateNSView(_ view: ScrollAttachment, context: Context) { view.configureIndicatorsSoon() }

    static func dismantleNSView(_ view: ScrollAttachment, coordinator: ()) {
        view.stopObserving()
    }

    final class ScrollAttachment: NSView {
        private let mode: Mode
        private var wheelMonitor: Any?
        private var styleObserver: NSObjectProtocol?
        private var configurationPending = false

        init(mode: Mode) {
            self.mode = mode
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Use init(mode:)") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }

            switch mode {
            case .horizontalHistory:
                wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.mapWheel(event) == true ? nil : event
                }
            case .verticalIndicators:
                styleObserver = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                                                      object: nil, queue: .main) { [weak self] _ in
                    self?.configureIndicatorsSoon()
                }
                configureIndicatorsSoon()
            }
        }

        override func layout() {
            super.layout()
            configureIndicatorsSoon()
        }

        func stopObserving() {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
            wheelMonitor = nil
            styleObserver = nil
        }

        func configureIndicatorsSoon() {
            guard mode == .verticalIndicators, window != nil, !configurationPending else { return }
            configurationPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                configurationPending = false
                guard let content = window?.contentView else { return }
                for scrollView in Self.scrollViews(in: content) where scrollView.hasVerticalScroller {
                    if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
                }
            }
        }

        private func mapWheel(_ event: NSEvent) -> Bool {
            guard let window, window.isVisible, event.window === window,
                  let distance = HistoryWheel.horizontalDistance(for: event) else { return false }

            // SwiftUI may host represented views in the same window rather than in the clip view.
            let candidates = enclosingScrollView.map { [$0] } ?? window.contentView.map(Self.scrollViews(in:)) ?? []
            for scrollView in candidates {
                let clipView = scrollView.contentView
                let location = clipView.convert(event.locationInWindow, from: nil)
                guard !scrollView.isHiddenOrHasHiddenAncestor, clipView.bounds.contains(location),
                      clipView.documentRect.width > clipView.bounds.width else { continue }
                let bounds = clipView.constrainBoundsRect(clipView.bounds.offsetBy(dx: -distance, dy: 0))
                clipView.scroll(to: bounds.origin)
                scrollView.reflectScrolledClipView(clipView)
                return true
            }
            return false
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            var matches: [NSScrollView] = []
            if let scroll = view as? NSScrollView { matches.append(scroll) }
            for child in view.subviews { matches.append(contentsOf: scrollViews(in: child)) }
            return matches
        }
    }
}
