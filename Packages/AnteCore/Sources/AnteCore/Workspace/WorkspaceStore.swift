// Packages/AnteCore/Sources/AnteCore/Workspace/WorkspaceStore.swift
import Foundation
import Observation
import os

/// The live, observable copy of `AppState`. Every mutation goes through here so the UI
/// re-renders and the file on disk follows a moment later (debounced, atomic).
@MainActor
@Observable
public final class WorkspaceStore {
    private static let logger = Logger(subsystem: "ante.term", category: "workspace")

    public private(set) var state: AppState
    public let loadNotice: StateStore.Notice?

    private let stateStore: StateStore
    private let saveDelay: Duration
    private var pendingSave: Task<Void, Never>?

    public init(stateStore: StateStore, saveDelay: Duration = .milliseconds(400)) {
        self.stateStore = stateStore
        self.saveDelay = saveDelay
        let result = stateStore.load()
        self.state = result.state
        self.loadNotice = result.notice
    }

    // MARK: - Projects

    @discardableResult
    public func addProject(rootDirectory: URL) -> Project {
        // Compare by path: `/a/b` and `/a/b/` are the same folder but different URLs.
        let normalized = URL(fileURLWithPath: rootDirectory.standardizedFileURL.path, isDirectory: true)
        if let existing = state.projects.first(where: { $0.rootDirectory.standardizedFileURL.path == normalized.path }) {
            return existing
        }
        let order = (state.projects.map(\.order).max() ?? -1) + 1
        let project = Project(name: normalized.lastPathComponent, rootDirectory: normalized, order: order)
        state.projects.append(project)
        scheduleSave()
        return project
    }

    public func removeProject(_ id: ProjectID) {
        let removedSessions = Set(state.sessions.filter { $0.projectID == id }.map(\.id))
        state.projects.removeAll { $0.id == id }
        state.sessions.removeAll { $0.projectID == id }
        if let focused = state.focusedSessionID, removedSessions.contains(focused) {
            state.focusedSessionID = firstVisibleSession()?.id
        }
        scheduleSave()
    }

    public func renameProject(_ id: ProjectID, to name: String) {
        guard let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
        state.projects[index].name = name
        scheduleSave()
    }

    // MARK: - Sessions

    @discardableResult
    public func addSession(in projectID: ProjectID, name: String? = nil, workingDirectory: URL? = nil,
                           isScratch: Bool = false) -> Session {
        let project = state.projects.first { $0.id == projectID }
        let siblings = state.sessions.filter { $0.projectID == projectID }
        let order = (siblings.map(\.order).max() ?? -1) + 1
        let session = Session(
            projectID: projectID,
            name: name ?? Self.nextName(among: siblings),
            workingDirectory: workingDirectory ?? project?.rootDirectory ?? FileManager.default.homeDirectoryForCurrentUser,
            order: order,
            createdAt: Self.now(),
            isScratch: isScratch
        )
        state.sessions.append(session)
        if !isScratch {
            state.focusedSessionID = session.id
        }
        scheduleSave()
        return session
    }

    public func removeSession(_ id: SessionID) {
        state.sessions.removeAll { $0.id == id }
        if state.focusedSessionID == id {
            state.focusedSessionID = firstVisibleSession()?.id
        }
        scheduleSave()
    }

    /// A rename by the user. Sticks: agent names no longer replace it.
    public func renameSession(_ id: SessionID, to name: String) {
        guard let index = state.sessions.firstIndex(where: { $0.id == id }) else { return }
        state.sessions[index].name = name
        state.sessions[index].isUserNamed = true
        scheduleSave()
    }

    /// A name an agent gave the session (Claude Code's title). Applied only while the user has
    /// not named the session themselves.
    public func setAutoName(_ name: String, for id: SessionID) {
        guard let index = state.sessions.firstIndex(where: { $0.id == id }),
              !state.sessions[index].isUserNamed, state.sessions[index].name != name else { return }
        state.sessions[index].name = name
        scheduleSave()
    }

    public func updateSession(_ id: SessionID, workingDirectory: URL? = nil, lastCommand: String? = nil) {
        guard let index = state.sessions.firstIndex(where: { $0.id == id }) else { return }
        if let workingDirectory { state.sessions[index].workingDirectory = workingDirectory }
        if let lastCommand { state.sessions[index].lastCommand = lastCommand }
        scheduleSave()
    }

    /// Moves a session to `order` within its project, renumbering siblings 0…n.
    public func moveSession(_ id: SessionID, toOrder order: Int) {
        guard let moving = state.sessions.first(where: { $0.id == id }) else { return }
        var siblings = state.sessions
            .filter { $0.projectID == moving.projectID && $0.id != id && !$0.isScratch }
            .sorted { $0.order < $1.order }
        siblings.insert(moving, at: max(0, min(order, siblings.count)))
        for (position, sibling) in siblings.enumerated() {
            if let index = state.sessions.firstIndex(where: { $0.id == sibling.id }) {
                state.sessions[index].order = position
            }
        }
        scheduleSave()
    }

    public func focus(_ id: SessionID?) {
        guard state.focusedSessionID != id else { return }
        state.focusedSessionID = id
        scheduleSave()
    }

    /// Sidebar sessions for a project: ordered, scratch excluded.
    public func visibleSessions(in projectID: ProjectID) -> [Session] {
        state.sessions(in: projectID).filter { !$0.isScratch }
    }

    /// All sidebar sessions in display order (projects, then sessions within each).
    public var allVisibleSessions: [Session] {
        state.orderedProjects.flatMap { visibleSessions(in: $0.id) }
    }

    /// The first project (in sidebar order) whose root contains `url`.
    public func orderedProjectContaining(_ url: URL) -> Project? {
        let path = url.standardizedFileURL.path
        return state.orderedProjects.first { project in
            let root = project.rootDirectory.standardizedFileURL.path
            return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    public var scratchSession: Session? {
        state.sessions.first { $0.isScratch }
    }

    public var focusedSession: Session? {
        guard let id = state.focusedSessionID else { return nil }
        return state.sessions.first { $0.id == id }
    }

    // MARK: - Persistence

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try stateStore.save(state)
        } catch {
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Waits for a pending debounced save (or performs it now). For quit paths and tests.
    public func flushPendingSave() async {
        if pendingSave != nil { saveNow() }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    private func firstVisibleSession() -> Session? {
        allVisibleSessions.first
    }

    /// Whole seconds: the state file's date format round-trips them exactly, so in-memory state
    /// equals reloaded state. Sub-second creation times buy nothing here.
    private static func now() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    private static func nextName(among siblings: [Session]) -> String {
        let taken = Set(siblings.map(\.name))
        if !taken.contains("Terminal") { return "Terminal" }
        var n = 2
        while taken.contains("Terminal \(n)") { n += 1 }
        return "Terminal \(n)"
    }
}
