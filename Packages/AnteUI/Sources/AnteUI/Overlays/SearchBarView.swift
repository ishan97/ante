// Packages/AnteUI/Sources/AnteUI/Overlays/SearchBarView.swift
import SwiftUI
import AnteTerm

/// ⌘F. Sits at the top-right of the focused pane. Return = next, ⇧Return = previous, ⎋ = close.
struct SearchBarView: View {
    let controller: TerminalSessionController
    let onClose: () -> Void

    @State private var term = ""
    @State private var caseSensitive = false
    @State private var summary: (index: Int, total: Int) = (0, 0)
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AnteStyle.textSecondary)
            TextField("Find", text: $term)
                .textFieldStyle(.plain)
                .font(AnteStyle.uiFont)
                .focused($focused)
                .onSubmit { run(.next) }
                .onChange(of: term) { _, _ in run(.next, fromStart: true) }
                .onExitCommand { close() }
                .frame(minWidth: 180)
            Text(summary.total == 0 ? (term.isEmpty ? "" : "0") : "\(summary.index) of \(summary.total)")
                .font(AnteStyle.captionFont)
                .foregroundStyle(AnteStyle.textSecondary)
                .frame(minWidth: 44, alignment: .trailing)
            Toggle(isOn: $caseSensitive) { Text("Aa").font(AnteStyle.captionFont) }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .help("Match case")
                .onChange(of: caseSensitive) { _, _ in run(.next, fromStart: true) }
            Button { run(.previous) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).keyboardShortcut(.return, modifiers: .shift).help("Previous (⇧⏎)")
            Button { run(.next) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).help("Next (⏎)")
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Close (⎋)")
        }
        .foregroundStyle(AnteStyle.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous).strokeBorder(AnteStyle.hairline))
        .onAppear { focused = true }
    }

    private func run(_ direction: SearchDirection, fromStart: Bool = false) {
        if fromStart { controller.clearSearch() }
        summary = controller.search(term, caseSensitive: caseSensitive, direction: direction)
    }

    private func close() {
        controller.clearSearch()
        onClose()
        controller.view.window?.makeFirstResponder(controller.view)
    }
}
