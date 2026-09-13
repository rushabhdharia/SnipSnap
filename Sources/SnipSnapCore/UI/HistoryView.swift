import SwiftUI
import AppKit

/// The panel's root view: a search field over a keyboard-navigable list,
/// split into a Pinned section and a Recent section.
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    let onPaste: (ClipItem) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    /// Flat, ordered list of what's currently shown (store keeps it sorted
    /// pinned-first, newest-first).
    private var visible: [ClipItem] {
        guard !query.isEmpty else { return store.items }
        let needle = query.lowercased()
        return store.items.filter { item in
            item.kind == .text && (store.resolveText(for: item)?.lowercased().contains(needle) ?? false)
        }
    }

    private var firstUnpinnedIndex: Int? {
        visible.firstIndex { !$0.pinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            grabStrip
            searchBar
            Divider()
            content
        }
        .onAppear {
            selection = 0
            searchFocused = true
        }
        .onChange(of: query) { selection = 0 }
        .onExitCommand(perform: onDismiss)
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.command),
               press.key == KeyEquivalent("p") {
                togglePinSelection()
                return .handled
            }
            if press.modifiers.contains(.command),
               let digit = Int(String(press.characters)), (1...9).contains(digit),
               digit - 1 < visible.count {
                onPaste(visible[digit - 1])
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Pieces

    /// A drag handle across the top — the panel is borderless, so this is
    /// the only way to move it (`WindowDragArea` makes it draggable).
    private var grabStrip: some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
        .background(WindowDragArea())
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search clipboard", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit(activateSelection)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState("Nothing copied yet", "Copied text and screenshots show up here.")
        } else if visible.isEmpty {
            emptyState("No matches", "Nothing in your history matches “\(query)”.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { pair in
                            let (idx, item) = pair
                            VStack(alignment: .leading, spacing: 2) {
                                if let header = sectionHeader(at: idx) {
                                    Text(header)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 14)
                                        .padding(.top, idx == 0 ? 6 : 12)
                                        .padding(.bottom, 2)
                                }
                                ItemRow(
                                    item: item,
                                    index: idx,
                                    isSelected: idx == selection,
                                    thumbnailURL: store.thumbnailURL(for: item),
                                    onActivate: { selection = idx; activateSelection() },
                                    onTogglePin: { store.togglePin(id: item.id) }
                                )
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .onChange(of: selection) { _, new in
                    guard visible.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(visible[new].id, anchor: .center) }
                }
            }
        }
    }

    private func sectionHeader(at index: Int) -> String? {
        let item = visible[index]
        if index == 0 {
            return item.pinned ? "PINNED" : "RECENT"
        }
        if item.pinned == false, visible[index - 1].pinned == true {
            return "RECENT"
        }
        return nil
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        selection = min(max(selection + delta, 0), visible.count - 1)
    }

    private func activateSelection() {
        guard visible.indices.contains(selection) else { return }
        onPaste(visible[selection])
    }

    private func togglePinSelection() {
        guard visible.indices.contains(selection) else { return }
        store.togglePin(id: visible[selection].id)
    }
}
