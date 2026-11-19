import SwiftUI

private enum HistoryScrollEdge { case leading }

struct HistoryView: View {
    private struct EntryClick {
        let id: String
        let location: CGPoint
        let time: TimeInterval
    }

    @ObservedObject var model: AppController
    @FocusState private var searchFocused: Bool
    @ViewState private var lastClick: EntryClick?
    private var horizontal: Bool { model.layout == .strip }

    var body: some View {
        VStack(spacing: 0) {
            header
            let clips = model.filtered
            if clips.isEmpty {
                emptyState
            } else {
                results(clips)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PanelBackground(fullWidth: horizontal))
        .environment(\.locale, AppText.locale)
        .onChange(of: model.historyPresentation) { _, _ in
            lastClick = nil
            searchFocused = true
        }
        .onChange(of: model.query) { _, _ in lastClick = nil }
        .onChange(of: model.layout) { _, _ in lastClick = nil }
        .onChange(of: model.historyFocusRequest) { _, _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        ToolbarGlassGroup {
            HStack(spacing: 9) {
                if !horizontal {
                    PanelDragHandle(help: AppText.History.drag)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(AppText.History.search, text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($searchFocused)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppText.text("清除搜索"))
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: HistoryStripLayout.searchHeight)
                .modifier(ToolbarGlass(shape: Capsule()))
                IconControl(symbol: "gearshape", label: AppText.text("设置")) { model.showSettingsFromHistory() }
                IconControl(symbol: "xmark", label: AppText.History.close) { model.hideHistory() }
            }
        }
        .padding(.horizontal, HistoryStripLayout.horizontalInset)
        .frame(height: horizontal ? HistoryStripLayout.searchHeight : 47)
        .padding(.top, horizontal ? HistoryStripLayout.searchTopInset : 0)
        .padding(.bottom, horizontal ? HistoryStripLayout.cardVerticalGap : 0)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.secondary)
            Text(model.query.isEmpty ? AppText.History.empty : AppText.text("没有匹配的记录"))
                .font(.system(size: 14, weight: .semibold))
            if model.query.isEmpty {
                Text(model.pasteboardDenied ? AppText.text("请在系统设置中允许 OwnClip 访问剪贴板。") : AppText.text("复制文本、图片或文件后会出现在这里。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func results(_ clips: [ClipSummary]) -> some View {
        ScrollViewReader { reader in
            Group {
                if horizontal {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            Color.clear.frame(width: 18, height: 1)
                                .id(HistoryScrollEdge.leading)
                                .accessibilityHidden(true)
                            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                                entry(clip, index: index)
                                    .padding(.trailing, index == clips.count - 1 ? 18 : 12)
                            }
                        }
                    }
                    .scrollIndicators(.never, axes: .horizontal)
                    .background { NativeScrollBehavior(mode: .horizontalHistory) }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                                entry(clip, index: index)
                            }
                        }
                        .padding(9)
                    }
                    .background { NativeScrollBehavior(mode: .verticalIndicators) }
                }
            }
            .onChange(of: model.selected) { _, selected in
                if horizontal && selected == clips.first?.id {
                    reader.scrollTo(HistoryScrollEdge.leading, anchor: .leading)
                } else if let selected {
                    reader.scrollTo(selected)
                }
            }
            .onAppear { scrollToStart(reader, first: clips.first?.id) }
            .onChange(of: model.historyPresentation) { _, _ in
                scrollToStart(reader, first: clips.first?.id)
            }
        }
        .frame(height: horizontal ? HistoryStripLayout.cardHeight : nil)
        .frame(maxHeight: horizontal ? nil : .infinity)
    }

    private func scrollToStart(_ reader: ScrollViewProxy, first: String?) {
        if horizontal {
            reader.scrollTo(HistoryScrollEdge.leading, anchor: .leading)
        } else if let first {
            reader.scrollTo(first, anchor: .top)
        }
    }

    private func entry(_ clip: ClipSummary, index: Int) -> some View {
        HistoryEntry(model: model, clip: clip, shortcut: model.shortcutForQuickItem(at: index),
                     isSelected: model.selected == clip.id, horizontal: horizontal)
            .id(clip.id)
            .onTapGesture(coordinateSpace: .global) { location in
                clickEntry(clip, at: location)
            }
            .contextMenu {
                Button(AppText.text("粘贴")) { model.paste(clip) }
                if clip.kind.canPasteAsText { Button(AppText.text("粘贴为纯文本")) { model.paste(clip, plainText: true) } }
                Button(AppText.text("复制到剪贴板")) { model.copy(clip) }
                Button(AppText.SequentialPaste.add) { model.addToStack(clip) }
                Divider()
                Button(AppText.text("删除记录"), role: .destructive) { model.removeHistory(clip) }
            }
            .accessibilityAddTraits(model.selected == clip.id ? [.isSelected] : [])
            .accessibilityAction(named: AppText.text("粘贴")) { model.paste(clip) }
    }

    private func clickEntry(_ clip: ClipSummary, at location: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let doubleClickDistance: CGFloat = 6
        if let lastClick, lastClick.id == clip.id, model.selected == clip.id,
           now - lastClick.time <= NSEvent.doubleClickInterval,
           abs(location.x - lastClick.location.x) <= doubleClickDistance,
           abs(location.y - lastClick.location.y) <= doubleClickDistance {
            self.lastClick = nil
            model.paste(clip)
        } else {
            lastClick = EntryClick(id: clip.id, location: location, time: now)
            if model.selected != clip.id { model.selected = clip.id }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let notice = model.notice {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                Text(notice.text).lineLimit(1).help(notice.text)
                Spacer(minLength: 0)
                Button(AppText.text("关闭提示")) { model.notice = nil }.buttonStyle(.borderless)
            } else {
                if let paste = model.shortcuts[.paste] { Text(AppText.format("%@ 粘贴", paste.label)) }
                if let plain = model.shortcuts[.pastePlain] { Text(AppText.format("%@ 纯文本", plain.label)) }
                Spacer(minLength: 0)
                if model.directPaste {
                    Text(AppText.format("%@ 条记录", model.filtered.count))
                } else if model.pastePermissionReview != .idle {
                    Button(AppText.text("查看自动粘贴权限")) { model.showPermissionSettings() }.buttonStyle(.borderless)
                } else {
                    Button(AppText.text("启用自动粘贴")) { model.requestPasteAccess() }.buttonStyle(.borderless)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 15)
        .frame(height: horizontal ? HistoryStripLayout.footerHeight : 34)
        .padding(.top, horizontal ? HistoryStripLayout.cardVerticalGap : 0)
        .padding(.bottom, horizontal ? HistoryStripLayout.bottomInset : 0)
    }
}

