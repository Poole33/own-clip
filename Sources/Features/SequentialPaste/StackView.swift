import SwiftUI

struct StackView: View {
    @ObservedObject var model: AppController

    var body: some View {
        VStack(spacing: 0) {
            ToolbarGlassGroup {
                HStack(spacing: 8) {
                    PanelDragHandle(help: AppText.SequentialPaste.drag)
                    Text(AppText.SequentialPaste.name).font(.system(size: 14, weight: .semibold)).fixedSize()
                    Spacer()
                    Picker(AppText.SequentialPaste.mode, selection: Binding(get: { model.stack.mode }, set: model.setStackPasteMode)) {
                        Text(AppText.SequentialPaste.consume).tag(StackPasteMode.pop)
                        Text(AppText.SequentialPaste.loop).tag(StackPasteMode.loop)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 170)
                    Text(AppText.format("%@ 条", model.stack.entries.count)).font(.caption).foregroundStyle(.secondary)
                    IconControl(symbol: "arrow.up.arrow.down", label: AppText.SequentialPaste.reverse) { model.reverseStack() }
                        .disabled(model.stack.entries.count < 2)
                    IconControl(symbol: "xmark", label: AppText.SequentialPaste.close) { model.closeStack() }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 43)
            if model.stack.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                    Text(AppText.SequentialPaste.empty).font(.callout)
                    Text(AppText.SequentialPaste.emptyHint).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let stack = model.stack
                let nextID = stack.next?.id
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(stack.entries.enumerated()), id: \.element.id) { index, entry in
                                let isNext = entry.id == nextID
                                let wasPasted = stack.pastedIDs.contains(entry.id)
                                HStack(spacing: 8) {
                                    Text("\(index + 1)").monospacedDigit()
                                        .foregroundStyle(PanelStyle.text(isSelected: isNext, secondary: true)).frame(width: 20)
                                    Image(systemName: entry.clip.kind.symbol)
                                        .foregroundStyle(PanelStyle.text(isSelected: isNext, secondary: true))
                                    Text(entry.clip.displayTitle)
                                        .lineLimit(1)
                                        .foregroundStyle(PanelStyle.text(isSelected: isNext, secondary: wasPasted))
                                        .accessibilityValue(isNext ? AppText.text("下一条") : (wasPasted ? AppText.text("本轮已粘贴") : ""))
                                    Spacer(minLength: 0)
                                    IconControl(symbol: "minus.circle", label: AppText.SequentialPaste.remove,
                                                foregroundColor: PanelStyle.text(isSelected: isNext, secondary: true)) {
                                        model.removeStackEntry(entry.id)
                                    }
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PanelStyle.background(isSelected: isNext),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: nextID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { NativeScrollBehavior(mode: .verticalIndicators) }
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PanelBackground())
        .environment(\.locale, AppText.locale)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice = model.notice {
                Text(notice.text).lineLimit(2).foregroundStyle(.secondary)
            }
            HStack {
                if model.contextKeysReady, let key = model.shortcuts[.stackPaste] {
                    Text("\(key.label) \(AppText.SequentialPaste.pasteNext)").foregroundStyle(.secondary)
                } else if model.directPaste && model.shortcuts[.stackPaste] != nil {
                    Button(AppText.text("启用输入监控")) { model.requestInputMonitoring() }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                } else if !model.directPaste && model.pastePermissionReview != .idle {
                    Button(AppText.text("查看自动粘贴权限")) { model.showPermissionSettings() }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                } else if !model.directPaste {
                    Button(AppText.text("启用自动粘贴")) { model.requestPasteAccess() }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button(nextButtonTitle) { model.pasteNextFromPanel() }
                    .disabled(model.stack.isEmpty)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var nextButtonTitle: String {
        if model.directPaste { return AppText.SequentialPaste.pasteNext }
        return model.stack.mode == .loop ? AppText.SequentialPaste.copyNext : AppText.SequentialPaste.takeNext
    }
}

