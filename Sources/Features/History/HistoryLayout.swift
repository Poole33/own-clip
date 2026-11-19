import CoreGraphics

enum HistoryLayout: String, CaseIterable, Identifiable {
    case strip, list
    var id: Self { self }
    var title: String { self == .strip ? AppText.text("底部长条") : AppText.text("浮动列表") }
}

// Bottom strip geometry, shared with native window sizing in WindowCoordinator.swift.
enum HistoryStripLayout {
    static let horizontalInset: CGFloat = 14
    // Search top matches its side margins; card gaps are adjusted separately.
    static let searchTopInset: CGFloat = horizontalInset
    static let cardVerticalGap: CGFloat = 20
    static let searchHeight: CGFloat = 30
    static let cardHeight: CGFloat = 175
    static let footerHeight: CGFloat = 14
    static let bottomInset: CGFloat = 10
    static var panelHeight: CGFloat {
        searchTopInset + cardVerticalGap * 2 + searchHeight + cardHeight + footerHeight + bottomInset
    }
}

