// Packages/AnteUI/Sources/AnteUI/Scratchpad/ScratchpadView.swift
import SwiftUI
import AnteCore

/// The popover behind the toolbar's checklist button: a to-do list with an inline "add" field,
/// done items tucked under a fold, and a notes pad below.
struct ScratchpadView: View {
    @Bindable var model: ScratchpadModel
    @Environment(\.anteAccent) private var accent
    @State private var draft = ""
    @State private var showDone = false
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            addRow
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.openItems) { item in
                        TodoRow(item: item, accent: accent, onToggle: { model.toggle(item.id) },
                                onRename: { model.rename(item.id, to: $0) }, onDelete: { model.remove(item.id) })
                    }
                    if model.openItems.isEmpty {
                        Text(model.doneItems.isEmpty ? "Nothing to do. Enjoy it." : "All done.")
                            .font(AnteStyle.uiFont)
                            .foregroundStyle(AnteStyle.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    if !model.doneItems.isEmpty {
                        doneFold
                        if showDone {
                            ForEach(model.doneItems) { item in
                                TodoRow(item: item, accent: accent, onToggle: { model.toggle(item.id) },
                                        onRename: { model.rename(item.id, to: $0) }, onDelete: { model.remove(item.id) })
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(minHeight: 120, maxHeight: 260)
            Divider().overlay(AnteStyle.hairline)
            notes
        }
        .frame(width: 340)
        .background(AnteStyle.paneBackground)
        .onAppear { addFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("To-do")
                .font(AnteStyle.uiFontSemibold)
                .foregroundStyle(AnteStyle.textPrimary)
            if model.openCount > 0 {
                Text("\(model.openCount)")
                    .font(AnteStyle.captionFont).monospacedDigit()
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(accent, in: Capsule())
            }
            Spacer()
            if !model.doneItems.isEmpty {
                Button("Clear done") { withAnimation(.easeOut(duration: 0.15)) { model.clearDone() } }
                    .buttonStyle(.plain)
                    .font(AnteStyle.captionFont)
                    .foregroundStyle(AnteStyle.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(draft.isEmpty ? AnteStyle.textSecondary : accent)
            TextField("", text: $draft, prompt: Text("Add a task, press Return"))
                .textFieldStyle(.plain)
                .font(AnteStyle.uiFont)
                .focused($addFocused)
                .onSubmit {
                    withAnimation(.easeOut(duration: 0.15)) { model.add(draft) }
                    draft = ""
                    addFocused = true
                }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(AnteStyle.rowHover, in: RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var doneFold: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showDone.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(showDone ? 90 : 0))
                Text("Done · \(model.doneItems.count)")
                Spacer()
            }
            .font(AnteStyle.captionFont)
            .foregroundStyle(AnteStyle.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(AnteStyle.captionFont).tracking(0.6)
                .foregroundStyle(AnteStyle.textSecondary)
                .padding(.horizontal, 14).padding(.top, 10)
            ZStack(alignment: .topLeading) {
                if model.notes.isEmpty {
                    Text("Jot something down…")
                        .font(AnteStyle.uiFont)
                        .foregroundStyle(AnteStyle.textSecondary.opacity(0.7))
                        .padding(.horizontal, 14).padding(.top, 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.notes)
                    .font(AnteStyle.uiFont)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 96, maxHeight: 140)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let accent: Color
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                ZStack {
                    Circle().strokeBorder(item.isDone ? accent : AnteStyle.textSecondary.opacity(0.7), lineWidth: 1.5)
                    if item.isDone {
                        Circle().fill(accent)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.black.opacity(0.85))
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "Mark as not done" : "Mark as done")
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(AnteStyle.uiFont)
                    .focused($focused)
                    .onSubmit { editing = false; onRename(draft) }
                    .onExitCommand { editing = false }
            } else {
                Text(item.text)
                    .font(AnteStyle.uiFont)
                    .foregroundStyle(item.isDone ? AnteStyle.textSecondary : AnteStyle.textPrimary)
                    .strikethrough(item.isDone, color: AnteStyle.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { draft = item.text; editing = true; focused = true }
            }
            if hovering && !editing {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(AnteStyle.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: AnteStyle.radius, style: .continuous).fill(hovering ? AnteStyle.rowHover : .clear))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: item.isDone)
    }
}
