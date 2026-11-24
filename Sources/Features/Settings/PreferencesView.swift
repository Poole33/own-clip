import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab { case general, shortcuts }

struct PreferencesView: View {
    private enum SectionID { case permissions }

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                Button(AppText.text("退出 OwnClip")) { NSApp.terminate(nil) }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .environment(\.locale, AppText.locale)
        .ignoresSafeArea(.container, edges: .top)
        .background { NativeScrollBehavior(mode: .verticalIndicators) }
    }

    private var general: some View {
        ScrollViewReader { proxy in
            generalForm
                .onChange(of: model.permissionSettingsFocusRequest, initial: true) { _, request in
                    guard request > 0 else { return }
                    // Let the form lay out before locating its permission section.
                    DispatchQueue.main.async {
                        guard model.permissionSettingsFocusRequest == request,
                              model.settingsTab == .general else { return }
                        proxy.scrollTo(SectionID.permissions, anchor: .bottom)
                    }
                }
        }
    }

    private var generalForm: some View {
        Form {
            Section(AppText.text("基础")) {
                UpdateSettingsRow(updates: model.updates)
                Toggle(AppText.text("开机时自动启动 OwnClip"), isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                Toggle(AppText.text("菜单栏图标"), isOn: Binding(get: { model.menuBarIconVisible }, set: model.setMenuBarIconVisible))
                if model.loginItemStatus == .requiresApproval {
                    Button(AppText.text("前往登录项设置并允许 OwnClip")) { model.openLoginItems() }
                }
                if let error = model.loginItemError {
                    Text(error.text).font(.caption).foregroundStyle(.red)
                }
                Picker(AppText.text("语言"), selection: Binding(get: { model.language }, set: model.setLanguage)) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
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
            Section(AppText.text("文件剪切")) {
                Toggle(AppText.text("Finder 文件剪切"), isOn: Binding(get: { model.finderCutEnabled }, set: model.setFinderCut))
                Text(AppText.text("选中文件按 ⌘X，进入目标文件夹按 ⌘V 完成移动。文字和文件名编辑使用系统原生剪切。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                pastePermissions
                if model.finderCutEnabled {
                    LabeledContent(AppText.text("文件剪切")) {
                        if model.accessibilityTrusted {
                            enabledPermissionStatus
                        } else {
                            Text(AppText.text("未获得授权"))
                        }
                    }
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
            }
            .id(SectionID.permissions)
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
        LabeledContent(AppText.text("自动粘贴")) {
            if model.directPaste && model.pastePermissionReview != .restartRequired {
                enabledPermissionStatus
            } else {
                Text(pastePermissionStatus)
            }
        }
        if model.restartedForPaste && model.directPaste && model.pastePermissionReview != .restartRequired {
            Text(AppText.text("授权已生效，可以开始使用自动粘贴。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        if !model.directPaste || model.pastePermissionReview.offersRestart {
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
                if model.restartedForPaste {
                    Text(AppText.text("请在系统设置中确认 OwnClip 已开启，再重新检查权限。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(AppText.text("打开系统设置")) { model.requestPasteAccess() }
                    Button(AppText.text("重新检查权限")) { model.reviewPasteAccess() }
                } else {
                    Button(AppText.text("启用自动粘贴")) { model.requestPasteAccess() }
                }
            }
            if let error = model.restartError {
                Text(error.text).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var enabledPermissionStatus: some View {
        Label(AppText.text("已启用"), systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    }

    private var pastePermissionStatus: String {
        if model.pastePermissionReview == .restartRequired { return AppText.text("已授权，需重启") }
        if model.directPaste { return AppText.text("已启用") }
        if model.restartedForPaste && model.pastePermissionReview == .idle { return AppText.text("权限尚未生效") }
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

private struct UpdateSettingsRow: View {
    @ObservedObject var updates: UpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if case let .available(version, pageURL) = updates.state {
                    Button {
                        NSWorkspace.shared.open(pageURL)
                    } label: {
                        Label(AppText.text("前往下载"), systemImage: "arrow.up.right")
                    }
                    .fixedSize()
                    status(AppText.format("新版本 %@ 可更新", version))
                } else {
                    Button(AppText.text("检查更新…")) { updates.check(manual: true) }
                        .disabled(updates.state == .checking)
                        .fixedSize()
                    switch updates.state {
                    case .checking: status(AppText.text("正在检查…"))
                    case .upToDate: status(AppText.text("已是最新版本"))
                    case .failed: status(AppText.text("暂时无法检查，请稍后重试"))
                    case .idle, .available: EmptyView()
                    }
                }
            }
            .buttonStyle(.bordered)

            if let version = updates.currentVersion {
                status(AppText.format("当前版本 %@", version))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

