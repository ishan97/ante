// Packages/AnteUI/Sources/AnteUI/Scratchpad/ScratchpadModel.swift
import Foundation
import Observation
import AnteCore

/// The to-do list and notes behind the toolbar's checklist button. Every change is saved a
/// moment later (coalesced), so typing a note never touches the disk per keystroke.
@MainActor
@Observable
public final class ScratchpadModel {
    public private(set) var pad: Scratchpad
    private let store: ScratchpadStore
    private var saveTask: Task<Void, Never>?

    public init(store: ScratchpadStore) {
        self.store = store
        self.pad = store.load()
    }

    public var openItems: [TodoItem] { pad.openItems }
    public var doneItems: [TodoItem] { pad.doneItems }
    public var openCount: Int { pad.openItems.count }

    public var notes: String {
        get { pad.notes }
        set { guard newValue != pad.notes else { return }; pad.notes = newValue; scheduleSave() }
    }

    @discardableResult
    public func add(_ text: String) -> TodoItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(text: String(trimmed.prefix(500)))
        pad.items.insert(item, at: 0)
        scheduleSave()
        return item
    }

    public func toggle(_ id: TodoItem.ID) {
        guard let i = pad.items.firstIndex(where: { $0.id == id }) else { return }
        pad.items[i].isDone.toggle()
        pad.items[i].doneAt = pad.items[i].isDone ? Date() : nil
        scheduleSave()
    }

    public func rename(_ id: TodoItem.ID, to text: String) {
        guard let i = pad.items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { pad.items.remove(at: i) } else { pad.items[i].text = String(trimmed.prefix(500)) }
        scheduleSave()
    }

    public func remove(_ id: TodoItem.ID) {
        pad.items.removeAll { $0.id == id }
        scheduleSave()
    }

    public func clearDone() {
        pad.items.removeAll(where: \.isDone)
        scheduleSave()
    }

    /// Writes now. Called on quit and by tests.
    public func flush() {
        saveTask?.cancel(); saveTask = nil
        try? store.save(pad)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            try? self.store.save(self.pad)
        }
    }
}
