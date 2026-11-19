import Combine
import Foundation

/// Validates, persists and registers shortcut settings as one operation.
final class ShortcutService: ObservableObject {
    @Published private(set) var bindings = ShortcutSettings()
    @Published var recording: ShortcutAction?
    @Published private(set) var error: AppMessage?
    var onAction: ((ShortcutAction) -> Void)?
    var onBindingsChange: (() -> Void)?

    private let preferences: UserDefaults
    private let globals = GlobalShortcuts()

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        globals.onAction = { [weak self] action in self?.onAction?(action) }
    }

    func start() {
        if let data = preferences.data(forKey: "shortcuts"), let decoded = try? JSONDecoder().decode(ShortcutSettings.self, from: data) {
            bindings = decoded
        }
        let failures = globals.installIndividually(bindings)
        if !failures.isEmpty {
            error = .init(AppText.format("无法注册：%@。可在设置里改键。", failures.map(\.title).joined(separator: AppText.listSeparator)))
        }
    }

    func record(_ action: ShortcutAction?) {
        error = nil
        recording = action
    }

    func change(_ action: ShortcutAction, binding: KeyBinding?) {
        if let binding, action != .close, (binding == .systemClose || binding == .systemCancel) {
            error = .init(AppText.text("Esc 和 ⌘W 保留用于取消或关闭当前窗口。请选择其他快捷键。"))
            return
        }
        if let binding, binding.modifiers == 0, [.stackPaste, .stackReverse, .finderCut, .finderMove].contains(action),
           !binding.isFunctionKey {
            error = .init(AppText.text("这项操作需要修饰键或 F1–F20，避免截获正在输入的文字。"))
            return
        }
        if let binding, let conflict = bindings.conflict(for: action, binding: binding) {
            error = .init(AppText.format("%@ 已用于「%@」。", binding.label, conflict.title))
            return
        }
        var proposed = bindings
        proposed.change(action, to: binding)
        applyShortcuts(proposed, globalsToUpdate: action.scope == .global ? [action] : [])
    }

    func restore(_ action: ShortcutAction) {
        if let standard = action.standard, let conflict = bindings.conflict(for: action, binding: standard) {
            error = .init(AppText.format("默认快捷键 %@ 已用于「%@」。", standard.label, conflict.title))
            return
        }
        var proposed = bindings
        proposed.restore(action)
        applyShortcuts(proposed, globalsToUpdate: action.scope == .global ? [action] : [])
    }

    func restoreAll() {
        applyShortcuts(ShortcutSettings(), globalsToUpdate: [.openHistory, .openStack])
    }

    private func applyShortcuts(_ proposed: ShortcutSettings, globalsToUpdate: [ShortcutAction]) {
        if let failed = globals.tryApply(proposed, actions: globalsToUpdate) {
            error = .init(AppText.format("系统无法注册「%@」的快捷键。请选择其他组合。", failed.title))
            return
        }
        bindings = proposed
        if let data = try? JSONEncoder().encode(proposed) { preferences.set(data, forKey: "shortcuts") }
        onBindingsChange?()
        recording = nil
        error = nil
    }

}
