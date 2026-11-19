import AppKit
import SwiftUI

struct HistoryEntry: View {
    @ObservedObject var model: AppController
    let clip: ClipSummary
    let shortcut: String?
    let isSelected: Bool
    let horizontal: Bool
    @ViewState private var thumbnail: NSImage?

    private var textColor: Color {
        PanelStyle.text(isSelected: isSelected)
    }

    private var detailColor: Color {
        PanelStyle.text(isSelected: isSelected, secondary: true)
    }

    var body: some View {
        Group {
            if horizontal { card } else { row }
        }
        .foregroundStyle(textColor)
        .background {
            RoundedRectangle(cornerRadius: horizontal ? 11 : 8)
                .fill(PanelStyle.background(isSelected: isSelected, isCard: horizontal))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task(id: clip.id) { thumbnail = await model.thumbnail(for: clip) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Label(clip.kind.label, systemImage: clip.kind.symbol)
                    .lineLimit(1)
                Spacer(minLength: 2)
                keyBadge
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(detailColor)
            if thumbnail != nil || clip.swatch != nil || clip.kind == .video || clip.kind == .image {
                visual.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 6))
                Text(clip.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
            } else {
                Text(clip.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Text(meta).font(.system(size: 10)).foregroundStyle(detailColor).lineLimit(1)
        }
        .padding(10)
        .frame(width: 210, height: HistoryStripLayout.cardHeight)
    }

    private var row: some View {
        HStack(spacing: 10) {
            visual.frame(width: 38, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(clip.kind.label) · \(meta)").font(.system(size: 10)).foregroundStyle(detailColor).lineLimit(1)
            }
            Spacer(minLength: 7)
            keyBadge
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
    }

    private var visual: some View {
        ZStack {
            Rectangle().fill(textColor.opacity(0.07))
            if let color = clip.swatch {
                Rectangle().fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
            } else if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else {
                Image(systemName: clip.kind.symbol).font(.system(size: horizontal ? 20 : 14)).foregroundStyle(detailColor)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var keyBadge: some View {
        if let shortcut {
            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(detailColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(textColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                .lineLimit(1)
        }
    }

    private var meta: String {
        let time = clip.date.formatted(.dateTime.hour().minute().locale(AppText.locale))
        return clip.source.isEmpty ? time : "\(clip.source) · \(time)"
    }
}

