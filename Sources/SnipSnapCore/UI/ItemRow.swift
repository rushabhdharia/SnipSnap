import SwiftUI
import AppKit

/// One row in the history list.
struct ItemRow: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let thumbnailURL: URL?
    let onActivate: () -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false
    @Environment(\.displayScale) private var displayScale

    /// Longest edge the preview may render at, in points — a real screen
    /// pixel cap so a small source image isn't upscaled and blurred.
    private static let maxPreviewPoints: CGFloat = 88

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Group {
            switch item.kind {
            case .text: textRow
            case .image: imageRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onActivate)
    }

    // MARK: - Text rows

    private var textRow: some View {
        HStack(spacing: 10) {
            placeholder(symbol: index < 9 ? "\(index + 1).square" : "doc.plaintext")
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .lineLimit(2)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                metaLine
            }

            Spacer(minLength: 4)
            pinButton
        }
    }

    // MARK: - Image rows

    /// A full-width preview instead of a small square thumbnail — a wide
    /// screenshot has no way to look sharp cropped into a 44x44 box.
    private var imageRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = thumbnailURL, let nsImage = NSImage(contentsOf: url) {
                let capPoints = min(Self.maxPreviewPoints, CGFloat(nsImage.size.height))
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: capPoints, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .quaternaryLabelColor), lineWidth: 1)
                    )
            } else {
                placeholder(symbol: "photo")
                    .frame(height: Self.maxPreviewPoints)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 6) {
                metaLine
                Spacer(minLength: 4)
                pinButton
            }
        }
    }

    // MARK: - Shared pieces

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(Self.relative.localizedString(for: item.createdAt, relativeTo: Date()))
            Text("·")
            Text(item.detail)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var pinButton: some View {
        if item.pinned || hovering {
            Button(action: onTogglePin) {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "Unpin" : "Pin")
        }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            Color(nsColor: .quaternaryLabelColor)
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}
