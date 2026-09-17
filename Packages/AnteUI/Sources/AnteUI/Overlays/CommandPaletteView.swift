// Packages/AnteUI/Sources/AnteUI/Overlays/CommandPaletteView.swift
import SwiftUI
import AnteCore

/// ⌘⇧P. Fuzzy list over sessions, projects, actions, themes, recent directories.
struct CommandPaletteView: View {
    @Environment(\.anteAccent) private var accent
    let items: [PaletteItem]
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [PaletteItem] {
        Array(FuzzyMatcher.rank(items, query: query, text: { $0.searchText }).prefix(40))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(AnteStyle.textSecondary)
                TextField("Type a command, session, or theme", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { activate() }
                    .onExitCommand { onClose() }
                    .onChange(of: query) { _, _ in selection = 0 }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
            }
            .padding(14)
            Divider().overlay(AnteStyle.hairline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == selection)
                                .id(item.id)
                                .onTapGesture { selection = index; activate() }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .onChange(of: selection) { _, _ in
                    if results.indices.contains(selection) { proxy.scrollTo(results[selection].id) }
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AnteStyle.hairline))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .onAppear { focused = true }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: item.kind))
                .frame(width: 16)
                .foregroundStyle(selected ? accent : AnteStyle.textSecondary)
            Text(item.title).font(AnteStyle.uiFont).foregroundStyle(AnteStyle.textPrimary).lineLimit(1)
            Spacer()
            if let subtitle = item.subtitle {
                Text(subtitle).font(AnteStyle.captionFont).foregroundStyle(AnteStyle.textSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous)
            .fill(selected ? AnteStyle.rowSelected : Color.clear))
        .contentShape(Rectangle())
    }

    private func symbol(for kind: PaletteItem.Kind) -> String {
        switch kind {
        case .session: return "terminal"
        case .project: return "folder"
        case .action: return "bolt"
        case .theme: return "paintpalette"
        case .directory: return "arrow.right.circle"
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func activate() {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        onClose()
        item.action()
    }
}
