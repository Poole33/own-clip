import Foundation

// Shared feature names and related copy for menus, settings, and panels.
enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic = "auto", english = "en", simplifiedChinese = "zh-Hans"

    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: return AppText.text("自动")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    static let preferenceKey = "appLanguage"

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .automatic
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard self == .automatic else { return self }
        for identifier in preferredLanguages {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            if parts.first == "en" { return .english }
            if parts.first == "zh" {
                if parts.contains("hant") { continue }
                if parts.contains("hans") { return .simplifiedChinese }
                if parts.contains("tw") || parts.contains("hk") || parts.contains("mo") { continue }
                return .simplifiedChinese
            }
        }
        return .english
    }
}

// Delay formatting stored notices until display, so visible errors switch languages too.
struct AppMessage {
    private let render: () -> String
    init(_ render: @autoclosure @escaping () -> String) { self.render = render }
    var text: String { render() }
}

enum AppText {
    static var language = AppLanguage.load()
    static var resolvedLanguage: AppLanguage { language.resolved() }
    static var locale: Locale { Locale(identifier: resolvedLanguage.rawValue) }
    static var listSeparator: String { resolvedLanguage == .simplifiedChinese ? "、" : ", " }

    static func text(_ key: String) -> String {
        resolvedLanguage == .simplifiedChinese ? key : (english[key] ?? key)
    }

    static func format(_ key: String, _ arguments: Any...) -> String {
        let singular = resolvedLanguage == .english && arguments.first as? Int == 1
        let template = singular ? (englishSingular[key] ?? text(key)) : text(key)
        return String(format: template, locale: locale, arguments: arguments.map { String(describing: $0) })
    }

    static func errorDescription(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static let englishSingular = ["%@ 条记录": "%@ item", "%@ 条": "%@ item", "%@ 天": "%@ day"]

    private static let english: [String: String] = [
        "自动": "Automatic",
        "语言": "Language",
        "通用": "General",
        "快捷键": "Shortcuts",
        "设置页面": "Settings page",
        "基础": "Basic",
        "检查更新…": "Check for Updates…",
        "正在检查…": "Checking…",
        "已是最新版本": "You're up to date",
        "暂时无法检查，请稍后重试": "Couldn't check for updates. Try again later.",
        "前往下载": "Open Download Page",
        "新版本 %@ 可更新": "Version %@ is available",
        "当前版本 %@": "Current version %@",
        "开机时自动启动 OwnClip": "Launch OwnClip at startup",
        "菜单栏图标": "Menu Bar Icon",
        "前往登录项设置并允许 OwnClip": "Allow OwnClip in Login Items",
        "显示方式": "Layout",
        "保留时间": "Keep history for",
        "存储位置": "Storage",
        "此 Mac": "This Mac",
        "剪切功能": "Cut",
        "Command + X 剪切文字和文件": "Cut text and files with Command + X",
        "开启后，可像在 Windows 一样剪切 Finder 文件，再到目标文件夹按 ⌘V 完成移动。": "Cut files in Finder, then press ⌘V in the destination folder to move them, just as on Windows.",
        "文件剪切": "File cutting",
        "已启用": "Enabled",
        "未获得授权": "Not authorized",
        "打开辅助功能设置": "Open Accessibility Settings",
        "打开输入监控设置": "Open Input Monitoring Settings",
        "请在系统设置中允许 OwnClip 访问剪贴板。": "Allow OwnClip to access the clipboard in System Settings.",
        "权限": "Permissions",
        "取消": "Cancel",
        "清空": "Clear",
        "自动粘贴": "Automatic paste",
        "授权已生效，可以开始使用自动粘贴。": "Access is active. You can now use automatic paste.",
        "请在系统设置中确认 OwnClip 已开启，再重新检查权限。": "Make sure OwnClip is enabled in System Settings, then check access again.",
        "系统已授权，重启 OwnClip 后即可生效。": "Access granted. Restart OwnClip to apply it.",
        "当前进程仍未获得权限。如果系统开关已开启，请重启 OwnClip。": "Access has not taken effect. If OwnClip is enabled in System Settings, restart the app.",
        "重启 OwnClip": "Restart OwnClip",
        "已授权，重启后生效": "Access granted. Restart to apply.",
        "重启 OwnClip 后，即可使用自动粘贴。": "Restart OwnClip to enable automatic paste.",
        "立即重启": "Restart Now",
        "返回系统设置": "Return to System Settings",
        "在系统设置里打开 OwnClip 的开关，再返回这里。": "Enable OwnClip in System Settings, then return here.",
        "重新检查权限": "Check access again",
        "启用自动粘贴": "Enable automatic paste",
        "如果系统开关已开启，请移除旧授权条目，再添加当前版本的 OwnClip.app。": "If OwnClip is already enabled, remove the old entry and add the current OwnClip.app again.",
        "等待系统授权": "Waiting for authorization",
        "已授权，需重启": "Authorized, restart required",
        "权限尚未生效": "Access not yet active",
        "恢复全部默认值": "Restore all defaults",
        "按下快捷键": "Press a shortcut",
        "未设置": "Not set",
        "禁用": "Disable",
        "恢复默认": "Restore default",
        "清除搜索": "Clear search",
        "设置": "Settings",
        "没有匹配的记录": "No matching items",
        "复制文本、图片或文件后会出现在这里。": "Copied text, images, and files will appear here.",
        "粘贴": "Paste",
        "粘贴为纯文本": "Paste as plain text",
        "复制到剪贴板": "Copy to clipboard",
        "删除记录": "Delete item",
        "关闭提示": "Dismiss",
        "纯文本": "Plain text",
        "查看自动粘贴权限": "Review paste access",
        "启用输入监控": "Enable input monitoring",
        "下一条": "Next item",
        "本轮已粘贴": "Pasted this cycle",
        "底部长条": "Bottom strip",
        "浮动列表": "Floating list",
        "设置…": "Settings…",
        "退出 OwnClip": "Quit OwnClip",
        "文件": "File",
        "关闭窗口": "Close Window",
        "OwnClip 设置": "OwnClip Settings",
        "Esc 和 ⌘W 保留用于取消或关闭当前窗口。请选择其他快捷键。": "Esc and ⌘W are reserved for canceling or closing the current window. Choose another shortcut.",
        "这项操作需要修饰键或 F1–F20，避免截获正在输入的文字。": "Use a modifier key or F1–F20 for this action to avoid intercepting typed text.",
        "已复制，按 ⌘V 手动粘贴": "Copied. Press ⌘V to paste.",
        "剪贴板已更新，请重新选择历史记录": "The clipboard changed. Select the history item again.",
        "这条记录没有可粘贴的文本。": "This item has no text to paste.",
        "无法写入系统剪贴板。": "Could not write to the system clipboard.",
        "请在目标应用中粘贴。": "Paste in the destination app.",
        "无法发送粘贴操作。可重试当前条目。": "Could not send the paste command. Try this item again.",
        "已放入剪贴板，请手动粘贴": "Copied to clipboard. Paste manually.",
        "已标记文件待移动": "Files marked for moving",
        "开启自动粘贴": "Enable automatic paste",
        "打开系统设置": "Open System Settings",
        "稍后": "Later",
        "未能重新打开 OwnClip。请从菜单栏退出后再打开应用。": "Could not reopen OwnClip. Quit from the menu bar, then open the app again.",
        "无法打开本地历史数据库。": "Could not open the local history database.",
        "文本": "Text",
        "富文本": "Rich text",
        "链接": "Link",
        "图片": "Image",
        "视频": "Video",
        "颜色": "Color",
        "空白文本": "Blank text",
        "剪贴板内容": "Clipboard content",
        "全局": "Global",
        "历史面板": "History panel",
        "面板通用": "All panels",
        "堆栈": "Stack",
        "Finder 文件移动": "Finder file moves",
        "向上选择": "Select above",
        "向下选择": "Select below",
        "向左选择": "Select left",
        "向右选择": "Select right",
        "关闭面板": "Close panel",
        "标记文件待移动": "Mark files for moving",
        "移动到当前目录": "Move to current folder",
        "剪贴板历史": "Clipboard History",
        "打开剪贴板历史": "Open Clipboard History",
        "关闭剪贴板历史": "Close Clipboard History",
        "OwnClip 剪贴板历史": "OwnClip Clipboard History",
        "搜索剪贴板历史": "Search Clipboard History",
        "还没有剪贴板历史": "No Clipboard History yet",
        "清空剪贴板历史…": "Clear Clipboard History…",
        "清空剪贴板历史？": "Clear Clipboard History?",
        "拖动以移动剪贴板历史窗口": "Drag to move Clipboard History",
        "允许 OwnClip 控制设备后，在剪贴板历史中按回车，就能把选中的内容粘贴回原应用。你也可以稍后在通用设置中开启。": "Allow OwnClip to control your computer so you can press Return in Clipboard History to paste into the previous app. You can also enable this later in General settings.",
        "顺序粘贴": "Sequential Paste",
        "打开顺序粘贴": "Open Sequential Paste",
        "关闭顺序粘贴": "Close Sequential Paste",
        "OwnClip 顺序粘贴": "OwnClip Sequential Paste",
        "加入顺序粘贴": "Add to Sequential Paste",
        "移除此条": "Remove item",
        "粘贴模式": "Paste mode",
        "用后移除": "Remove after use",
        "循环使用": "Loop",
        "反转顺序": "Reverse order",
        "粘贴下一条": "Paste next",
        "复制下一条": "Copy next",
        "取出下一条": "Take next",
        "复制或剪切多条内容，按顺序逐条粘贴": "Copy or cut multiple items, then paste them in order",
        "也可以从剪贴板历史的条目菜单添加。": "You can also add items from the Clipboard History item menu.",
        "拖动以移动顺序粘贴窗口": "Drag to move Sequential Paste",
        "OwnClip 会删除本地剪贴板历史，顺序粘贴中的对应条目也会移除。": "OwnClip will delete local Clipboard History and remove the corresponding items from Sequential Paste.",
        "%@ 粘贴": "%@ Paste",
        "%@ 纯文本": "%@ Plain text",
        "%@ 条记录": "%@ items",
        "%@ 条": "%@ items",
        "%@ 天": "%@ days",
        "%@选项": "%@ options",
        "粘贴第 %@ 条": "Paste item %@",
        "源文件已不可用：%@": "Source file is unavailable: %@",
        "无法读取这条记录。%@": "Could not read this item. %@",
        "无法更新本地历史（%@）。": "Could not update local history (%@).",
        "%@ 已用于「%@」。": "%@ is already used for “%@”.",
        "默认快捷键 %@ 已用于「%@」。": "The default shortcut %@ is already used for “%@”.",
        "系统无法注册「%@」的快捷键。请选择其他组合。": "Could not register the shortcut for “%@”. Choose another combination.",
        "无法注册：%@。可在设置里改键。": "Could not register: %@. Change the shortcuts in Settings.",
        "%@ 等 %@ 项": "%@ and others (%@ items)",
    ]

    enum History {
        static var name: String { text("剪贴板历史") }
        static var open: String { text("打开剪贴板历史") }
        static var close: String { text("关闭剪贴板历史") }
        static var windowTitle: String { text("OwnClip 剪贴板历史") }
        static var search: String { text("搜索剪贴板历史") }
        static var empty: String { text("还没有剪贴板历史") }
        static var clear: String { text("清空剪贴板历史…") }
        static var confirmClear: String { text("清空剪贴板历史？") }
        static var drag: String { text("拖动以移动剪贴板历史窗口") }
        static var pastePermission: String { text("允许 OwnClip 控制设备后，在剪贴板历史中按回车，就能把选中的内容粘贴回原应用。你也可以稍后在通用设置中开启。") }
    }

    enum SequentialPaste {
        static var name: String { text("顺序粘贴") }
        static var open: String { text("打开顺序粘贴") }
        static var close: String { text("关闭顺序粘贴") }
        static var windowTitle: String { text("OwnClip 顺序粘贴") }
        static var add: String { text("加入顺序粘贴") }
        static var remove: String { text("移除此条") }
        static var mode: String { text("粘贴模式") }
        static var consume: String { text("用后移除") }
        static var loop: String { text("循环使用") }
        static var reverse: String { text("反转顺序") }
        static var pasteNext: String { text("粘贴下一条") }
        static var copyNext: String { text("复制下一条") }
        static var takeNext: String { text("取出下一条") }
        static var empty: String { text("复制或剪切多条内容，按顺序逐条粘贴") }
        static var emptyHint: String { text("也可以从剪贴板历史的条目菜单添加。") }
        static var drag: String { text("拖动以移动顺序粘贴窗口") }
        static var clearHistoryWarning: String { text("OwnClip 会删除本地剪贴板历史，顺序粘贴中的对应条目也会移除。") }
    }
}
