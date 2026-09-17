// Packages/AnteTerm/Sources/AnteTerm/Session/TerminalSessionController.swift
import AppKit
import Observation
import os
import SwiftTerm
import AnteCore

public enum SessionProcessState: Equatable, Sendable {
    case idle
    case running
    case exited(code: Int32?)
    case failed(message: String)
}

/// Owns one terminal view and its child process. Publishes the shell's semantic events onto
/// the shared `RunEventBus` stamped with this session's ID, and tracks title, cwd, and exit.
@MainActor
@Observable
public final class TerminalSessionController: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
    private static let logger = Logger(subsystem: "ante.term", category: "session")

    public let sessionID: SessionID
    public let view: AnteTerminalView
    public private(set) var state: SessionProcessState = .idle
    public private(set) var title: String = ""
    /// The title parsed as an agent's status line, when it is one. Real-time and hook-free.
    public private(set) var agentTitle: AgentTitle?
    /// Called on the main thread whenever the agent title changes.
    public var onAgentTitle: ((AgentTitle?) -> Void)?
    /// Called on the main thread when the shell reports a new working directory (OSC 7).
    public var onDirectoryChanged: ((URL) -> Void)?
    /// The program's latest OSC 9 notification ("Claude needs your permission") and when it came.
    public private(set) var lastNotification: (message: String, at: Date)?
    public private(set) var currentDirectory: URL?
    /// Whether the shell is between OSC 133;C and 133;D — i.e. a command is executing.
    public private(set) var activity: SessionActivity = .idle
    /// Exit code of the most recent finished command, from OSC 133;D.
    public private(set) var lastExitCode: Int?
    /// Commands the user has started in this pane (OSC 133;C). Zero means an untouched shell.
    public private(set) var commandsRun = 0
    /// When the terminal last received output. Feeds the "waiting for you" heuristic.
    public private(set) var lastOutputAt = Date()
    /// When the user last typed or pasted into this pane. Answers a "waiting for you" state.
    public private(set) var lastInputAt: Date?
    /// Output before this instant is a redraw (attach/resize), not the program doing work.
    private var ignoreOutputUntil = Date.distantPast
    /// Who is in the foreground of the pty, sampled every two seconds while running.
    public private(set) var foreground: ForegroundInfo?
    /// What the foreground process is, as far as Ante can tell.
    public var agent: AgentKind {
        foreground.map { AgentKind.classify(commandLine: $0.commandLine) } ?? .shell
    }
    /// The foreground command line when it is not a known agent and not the shell.
    public var foregroundCommand: String? {
        guard agent == .command, let info = foreground else { return nil }
        return info.commandLine.joined(separator: " ")
    }
    private var probeTimer: Timer?

    private let launch: ShellLaunch
    private let workingDirectory: URL
    private let bus: RunEventBus
    let promptMarks = PromptMarks()
    /// Bumps (at most ~30×/s) when the view scrolls or new output arrives. Views that draw over
    /// the terminal read it to know when to redraw.
    public private(set) var contentVersion = 0
    private var contentTick: Task<Void, Never>?

    public init(sessionID: SessionID, launch: ShellLaunch, workingDirectory: URL, bus: RunEventBus,
                options: TerminalOptions = TerminalOptions(scrollback: 10_000)) {
        self.sessionID = sessionID
        self.launch = launch
        self.workingDirectory = workingDirectory
        self.bus = bus
        self.currentDirectory = workingDirectory
        self.view = AnteTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), font: nil, options: options)
        super.init()
        view.linkBaseDirectory = workingDirectory
        view.processDelegate = self
        view.onScrollOrContentChange = { [weak self] in self?.noteContentChange() }
        // Off by default in SwiftTerm; without it `rangeChanged` never fires and overlays such as
        // the gutter only repaint on scroll or at the next prompt (stale dots after a clear).
        view.notifyUpdateChanges = true
        view.onOutput = { [weak self] in
            // Process queue; hop to main in FIFO order (unstructured Tasks are not ordered).
            let now = Date()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, now > self.ignoreOutputUntil, now.timeIntervalSince(self.lastOutputAt) > 0.2 else { return }
                    self.lastOutputAt = now
                }
            }
        }
        view.onUserInput = { [weak self] in self?.lastInputAt = Date() }
        view.onAttached = { [weak self] in self?.ignoreRedrawOutput() }
        let marks = promptMarks
        view.onScreenCleared = { marks.invalidateAll() }
        view.onSemanticEventSync = { [weak view] event in
            // Process queue, right after the terminal consumed the bytes up to this event.
            // (`weak`: the closure lives on the view; a strong capture would keep it alive forever.)
            guard let terminal = view?.getTerminal() else { return }
            switch event {
            case .promptStarted:
                if let origin = terminal.activeSemanticPromptOrigin, let line = terminal.bufferLine(atRow: origin.row) {
                    marks.record(prompt: line)
                }
            case let .commandFinished(exitCode):
                marks.attachExitCode(exitCode)
            case .commandStarted, .cwdChanged, .notification:
                break
            }
        }
        view.onSemanticEvents = { [weak self] events in
            // Runs on SwiftTerm's process queue.
            guard let self else { return }
            let id = self.sessionID
            let now = Date()
            for event in events {
                self.bus.publish(RunEvent(sessionID: id, event: event, at: now))
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.absorb(events) }
            }
        }
    }

    private func absorb(_ events: [SemanticEvent]) {
        for event in events {
            switch event {
            case .commandStarted:
                activity = .commandRunning
                commandsRun += 1
            case let .commandFinished(exitCode):
                activity = .idle
                lastExitCode = exitCode
            case let .cwdChanged(url):
                currentDirectory = url
                view.linkBaseDirectory = url
                onDirectoryChanged?(url)
            case .promptStarted:
                activity = .idle
            case let .notification(message):
                lastNotification = (message, Date())
            }
        }
        noteContentChange()
    }

    /// For callers outside this file that changed the buffer directly.
    func contentDidChange() { noteContentChange() }

    private func noteContentChange() {
        guard contentTick == nil else { return }
        contentTick = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard let self else { return }
            self.contentTick = nil
            self.contentVersion &+= 1
        }
    }

    public func apply(_ appearance: TerminalAppearance) {
        appearance.apply(to: view)
    }

    /// Sets the terminal background's opacity and picks the renderer for it: SwiftTerm's Metal
    /// renderer is faster but composites the background as opaque, so a translucent terminal
    /// (wallpaper, window opacity) draws with the CPU renderer instead.
    public func setBackgroundOpacity(_ opacity: CGFloat) {
        view.backgroundOpacity = opacity
        applyRenderer()
    }

    public func applyRenderer() {
        try? view.setUseMetal(view.backgroundOpacity >= 1)
    }

    public func start() {
        guard state == .idle || isFinished else { return }
        guard FileManager.default.isExecutableFile(atPath: launch.executable) else {
            state = .failed(message: "shell not found or not executable: \(launch.executable)")
            Self.logger.error("spawn refused: \(self.launch.executable, privacy: .public)")
            return
        }
        state = .running
        activity = .idle
        lastOutputAt = Date()
        startProbing()
        view.startProcess(
            executable: launch.executable,
            args: launch.arguments,
            environment: launch.environment,
            execName: nil,
            currentDirectory: (currentDirectory ?? workingDirectory).path
        )
    }

    public func restart() {
        guard isFinished else { return }
        state = .idle
        start()
    }

    /// Ends the session the way closing a terminal window does: SIGHUP to the whole process
    /// group (the shell and anything it is running in the foreground), then SIGKILL if the
    /// group is still alive two seconds later.
    public func terminate() {
        stopProbing()
        guard state == .running, let pid = view.process?.shellPid, pid > 0 else { return }
        killpg(pid, SIGHUP)
        // The follow-up must not depend on this controller staying alive: closing a pane drops it
        // right after this call. `kill(pid, 0)` says whether the group leader is still there.
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            // Still there *and* still the leader of its own group (a reused pid would not be).
            if kill(pid, 0) == 0, getpgid(pid) == pid { killpg(pid, SIGKILL) }
        }
    }

    private var isFinished: Bool {
        switch state {
        case .exited, .failed: return true
        case .idle, .running: return false
        }
    }

    // MARK: - LocalProcessTerminalViewDelegate (delivered on the main thread by SwiftTerm)

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        ignoreRedrawOutput()
    }

    /// Full-screen programs repaint after SIGWINCH or a window attach; that burst must not look
    /// like activity, or a session waiting on the user flips to "Working" every time it is shown.
    private func ignoreRedrawOutput() {
        ignoreOutputUntil = Date().addingTimeInterval(1.5)
    }

    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title
        let parsed = AgentTitle.parse(title)
        guard parsed != agentTitle else { return }
        agentTitle = parsed
        onAgentTitle?(parsed)
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Ante parses OSC 7 itself; this callback is intentionally ignored so there is one source of truth.
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        state = .exited(code: Self.normalizedExitCode(exitCode))
        activity = .idle
        stopProbing()
        foreground = nil
    }

    // MARK: - Foreground probing

    private func startProbing() {
        stopProbing()
        probe()
        probeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.probe() }
        }
    }

    private func stopProbing() {
        probeTimer?.invalidate()
        probeTimer = nil
    }

    private func probe() {
        guard state == .running, let fd = view.process?.childfd, fd >= 0 else { return }
        Task.detached(priority: .utility) { [weak self] in
            let info = ForegroundProbe.foreground(ptyFD: fd)
            await MainActor.run { [weak self] in
                guard let self, self.state == .running else { return }
                if self.foreground != info { self.foreground = info }
            }
        }
    }

    /// SwiftTerm 1.20.0 passes the raw `wait(2)` status. Decode it the way `WEXITSTATUS` /
    /// `WIFSIGNALED` do: a normal exit yields its 0–255 code, a signal death yields nil.
    static func normalizedExitCode(_ rawStatus: Int32?) -> Int32? {
        guard let status = rawStatus else { return nil }
        if status & 0x7f == 0 {
            return (status >> 8) & 0xff
        }
        return nil
    }
}
