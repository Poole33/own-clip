import ServiceManagement
import SwiftUI

enum SettingsTab { case general, shortcuts }

struct PreferencesView: View {
    @ObservedObject var model: AppController
    @ViewState private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            Picker(AppText.text("设置页面"), selection: $model.settingsTab) {
                Text(AppText.text("通用")).tag(SettingsTab.general)
                Text(AppText.text("快捷键")).tag(SettingsTab.shortcuts)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
            .frame(maxWidth: .infinity)
            .frame(height: 52)

            ZStack {
                general
                    .opacity(model.settingsTab == .general ? 1 : 0)
                    .allowsHitTesting(model.settingsTab == .general)
                    .accessibilityHidden(model.settingsTab != .general)
                keyBindings
                    .opacity(model.settingsTab == .shortcuts ? 1 : 0)
                    .allowsHitTesting(model.settingsTab == .shortcuts)
                    .accessibilityHidden(model.settingsTab != .shortcuts)
            }
            .padding([.horizontal, .bottom], 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.locale, AppText.locale)
        .ignoresSafeArea(.container, edges: .top)
        .background { NativeScrollBehavior(mode: .verticalIndicators) }
    }

    private var general: some View {
        Form {
            Section(AppText.text("语言")) {
                Picker(AppText.text("语言"), selection: Binding(get: { model.language }, set: model.setLanguage)) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            }
            Section(AppText.text("启动")) {
                Toggle(AppText.text("登录时自动启动 OwnClip"), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                if model.loginItemStatus == .requiresApproval {
                    Button(AppText.text("前往登录项设置并允许 OwnClip")) { model.openLoginItems() }
                }
                if let error = model.loginItemError {
                    Text(error.text).font(.caption).foregroundStyle(.red)
                }
            }
            Section(AppText.History.name) {
                Picker(AppText.text("显示方式"), selection: Binding(get: { model.layout }, set: model.setLayout)) {
                    ForEach(HistoryLayout.allCases) { Text($0.title).tag($0) }
                }
                Picker(AppText.text("保留时间"), selection: Binding(get: { model.days }, set: model.setDays)) {
                    ForEach(1...7, id: \.self) { Text(AppText.format("%@ 天", $0)).tag($0) }
                }
                LabeledContent(AppText.text("存储位置")) {
                    Text(AppText.text("此 Mac")).foregroundStyle(.secondary)
                }
                Button(AppText.History.clear, role: .destructive) { confirmClear = true }
                    .disabled(model.history.isEmpty)
            }
            Section(AppText.text("剪切功能")) {
                Toggle(AppText.text("Command + X 剪切文字和文件"), isOn: Binding(get: { model.finderCutEnabled }, set: model.setFinderCut))
                Text(AppText.text("开启后，可像在 Windows 一样剪切 Finder 文件，再到目标文件夹按 ⌘V 完成移动。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                pastePermissions
                if model.finderCutEnabled {
                    LabeledContent(AppText.text("文件剪切"), value: model.accessibilityTrusted ? AppText.text("已启用") : AppText.text("未获得授权"))
                    if !model.accessibilityTrusted { Button(AppText.text("打开辅助功能设置")) { model.requestAccessibility() } }
                }
                if model.directPaste && !model.contextKeysReady && model.contextKeysWanted {
                    Button(AppText.text("打开输入监控设置")) { model.requestInputMonitoring() }
                }
                if model.pasteboardDenied {
                    Text(AppText.text("请在系统设置中允许 OwnClip 访问剪贴板。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(AppText.text("权限"))
            } footer: {
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text(AppText.format("版本 %@", version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
            }
        }
        .formStyle(.grouped)
        .alert(AppText.History.confirmClear, isPresented: $confirmClear) {
            Button(AppText.text("取消"), role: .cancel) {}
            Button(AppText.text("清空"), role: .destructive) { model.clearHistory() }
        } message: {
            Text(AppText.SequentialPaste.clearHistoryWarning)
        }
    }

    @ViewBuilder private var pastePermissions: some View {
        LabeledContent(AppText.text("自动粘贴"), value: pastePermissionStatus)
        if !model.directPaste {
            if model.pastePermissionReview.offersRestart {
                Text(model.pastePermissionReview == .restartRequired
                     ? AppText.text("系统已授权，重启 OwnClip 后即可生效。")
                     : AppText.text("当前进程仍未获得权限。如果系统开关已开启，请重启 OwnClip。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(AppText.text("重启 OwnClip")) { model.restartForPastePermission() }
                    .disabled(model.restartingForPaste)
                Button(AppText.text("返回系统设置")) { model.requestPasteAccess() }
            } else if model.pastePermissionReview == .checking {
                Text(AppText.text("在系统设置里打开 OwnClip 的开关，再返回这里。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(AppText.text("重新检查权限")) { model.reviewPasteAccess() }
                Button(AppText.text("返回系统设置")) { model.requestPasteAccess() }
            } else {
                Button(AppText.text("启用自动粘贴")) { model.requestPasteAccess() }
                if model.restartedForPaste {
                    Text(AppText.text("如果系统开关已开启，请移除旧授权条目，再添加当前版本的 OwnClip.app。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.restartError {
                Text(error.text).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var pastePermissionStatus: String {
        if model.directPaste { return AppText.text("已启用") }
        switch model.pastePermissionReview {
        case .idle: return AppText.text("未获得授权")
        case .checking: return AppText.text("等待系统授权")
        case .restartRequired: return AppText.text("已授权，需重启")
        case .restartSuggested: return AppText.text("权限尚未生效")
        }
    }

    private var keyBindings: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let message = model.shortcutError {
                Label(message.text, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
            }
            Form {
                ForEach(ShortcutScope.allCases, id: \.self) { scope in
                    Section(scope.title) {
                        ForEach(ShortcutAction.allCases.filter { $0.scope == scope }) { shortcutRow($0) }
                    }
                }
            }
            .formStyle(.grouped)
            Button(AppText.text("恢复全部默认值")) { model.restoreShortcuts() }
                .padding(.leading, 12)
                .padding(.bottom, 8)
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        HStack(spacing: 6) {
            Text(action.title)
            Spacer(minLength: 8)
            if model.recording == action {
                Text(AppText.text("按下快捷键")).font(.callout).foregroundStyle(Color.accentColor)
                Button(AppText.text("取消")) { model.recordShortcut(nil) }
            } else {
                Button(model.shortcuts[action]?.label ?? AppText.text("未设置")) {
                    model.recordShortcut(action)
                }
                .font(.system(.callout, design: .monospaced))
            }
            Menu {
                Button(AppText.text("禁用")) { model.changeShortcut(action, binding: nil) }
                Button(AppText.text("恢复默认")) { model.restoreShortcut(action) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(AppText.format("%@选项", action.title))
        }
    }
}

