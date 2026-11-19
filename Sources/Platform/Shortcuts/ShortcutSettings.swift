import AppKit
import Carbon
import CoreGraphics
import Foundation

enum ShortcutScope: String, CaseIterable {
    // Keep internal identifiers stable; use title for all displayed labels.
    case global = "全局"
    case historyPanel = "历史面板"
    case panel = "面板通用"
    case stack = "堆栈"
    case finder = "Finder 文件移动"

    var title: String {
        switch self {
        case .historyPanel: return AppText.History.name
        case .stack: return AppText.SequentialPaste.name
        default: return AppText.text(rawValue)
        }
    }
}

enum ShortcutAction: Int, Codable, CaseIterable, Identifiable {
    case openHistory = 1, openStack
    case paste, pastePlain, previous, next, left, right, close
    case quick1, quick2, quick3, quick4, quick5, quick6, quick7, quick8, quick9, quick10
    case stackPaste, stackReverse, finderCut, finderMove

    var id: Int { rawValue }

    var quickIndex: Int? {
        guard (Self.quick1.rawValue...Self.quick10.rawValue).contains(rawValue) else { return nil }
        return rawValue - Self.quick1.rawValue
    }

    var scope: ShortcutScope {
        switch self {
        case .openHistory, .openStack: .global
        case .paste, .pastePlain, .quick1, .quick2, .quick3, .quick4, .quick5, .quick6, .quick7, .quick8, .quick9, .quick10: .historyPanel
        case .previous, .next, .left, .right, .close: .panel
        case .stackPaste, .stackReverse: .stack
        case .finderCut, .finderMove: .finder
        }
    }

    var title: String {
        if let index = quickIndex { return AppText.format("粘贴第 %@ 条", index + 1) }
        switch self {
        case .openHistory: return AppText.History.open
        case .openStack: return AppText.SequentialPaste.open
        case .paste: return AppText.text("粘贴")
        case .pastePlain: return AppText.text("粘贴为纯文本")
        case .previous: return AppText.text("向上选择")
        case .next: return AppText.text("向下选择")
        case .left: return AppText.text("向左选择")
        case .right: return AppText.text("向右选择")
        case .close: return AppText.text("关闭面板")
        case .stackPaste: return AppText.SequentialPaste.pasteNext
        case .stackReverse: return AppText.SequentialPaste.reverse
        case .finderCut: return AppText.text("标记文件待移动")
        case .finderMove: return AppText.text("移动到当前目录")
        default: return ""
        }
    }

    var standard: KeyBinding? {
        if let index = quickIndex {
            let codes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
                         kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
            return KeyBinding(codes[index], .command, label: String((index + 1) % 10))
        }
        switch self {
        case .openHistory: return KeyBinding(kVK_ANSI_V, [.command, .shift], label: "V")
        case .openStack: return KeyBinding(kVK_ANSI_C, [.command, .shift], label: "C")
        case .paste: return KeyBinding(kVK_Return, label: "Return")
        case .pastePlain: return KeyBinding(kVK_Return, .command, label: "Return")
        case .previous: return KeyBinding(kVK_UpArrow, label: "↑")
        case .next: return KeyBinding(kVK_DownArrow, label: "↓")
        case .left: return KeyBinding(kVK_LeftArrow, label: "←")
        case .right: return KeyBinding(kVK_RightArrow, label: "→")
        case .close: return KeyBinding(kVK_Escape, label: "Esc")
        case .stackPaste, .finderMove: return .systemPaste
        case .finderCut: return KeyBinding(kVK_ANSI_X, .command, label: "X")
        default: return nil
        }
    }

    func overlaps(_ other: Self) -> Bool {
        if scope == .global || other.scope == .global { return true }
        if scope == other.scope { return true }
        let scopes = Set([scope, other.scope])
        if scopes == Set([.stack, .finder]) {
            return Set([self, other]) != Set([.stackPaste, .finderMove])
        }
        return scopes == Set([.panel, .historyPanel]) || scopes == Set([.panel, .stack])
    }
}

struct ShortcutSettings: Codable {
    var custom: [ShortcutAction: KeyBinding] = [:]
    var disabled: Set<ShortcutAction> = []

    subscript(action: ShortcutAction) -> KeyBinding? {
        if disabled.contains(action) { return nil }
        return custom[action] ?? action.standard
    }

    mutating func change(_ action: ShortcutAction, to binding: KeyBinding?) {
        custom[action] = binding
        if binding == nil { disabled.insert(action) } else { disabled.remove(action) }
    }

    mutating func restore(_ action: ShortcutAction) {
        custom.removeValue(forKey: action)
        disabled.remove(action)
    }

    func conflict(for action: ShortcutAction, binding: KeyBinding) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != action && action.overlaps($0) && self[$0] == binding }
    }
}

