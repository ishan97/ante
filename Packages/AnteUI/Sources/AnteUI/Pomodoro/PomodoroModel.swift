// Packages/AnteUI/Sources/AnteUI/Pomodoro/PomodoroModel.swift
import Foundation
import Observation
import AppKit
import UserNotifications

/// A focus timer in the toolbar: 25 minutes on, 5 off, with a sound and a notification at each
/// turn. Durations are remembered in preferences; the count of focus blocks resets each day.
@MainActor
@Observable
public final class PomodoroModel {
    public enum Phase: String, Sendable { case focus, shortBreak, longBreak
        public var label: String {
            switch self { case .focus: return "Focus"; case .shortBreak: return "Break"; case .longBreak: return "Long break" }
        }
    }
    public enum State: Sendable { case idle, running, paused }

    public private(set) var phase: Phase = .focus
    public private(set) var state: State = .idle
    public private(set) var remaining: TimeInterval
    /// Focus blocks finished today.
    public private(set) var completedToday = 0
    // Clamped in the setters (an @Observable stored property must not reassign itself in didSet).
    private var focusStorage: Int
    private var breakStorage: Int
    private var longBreakStorage: Int
    public var focusMinutes: Int {
        get { focusStorage }
        set { focusStorage = max(1, min(120, newValue)); persist(); if state == .idle, phase == .focus { remaining = duration(of: .focus) } }
    }
    public var breakMinutes: Int {
        get { breakStorage }
        set { breakStorage = max(1, min(60, newValue)); persist(); if state == .idle, phase == .shortBreak { remaining = duration(of: .shortBreak) } }
    }
    public var longBreakMinutes: Int {
        get { longBreakStorage }
        set { longBreakStorage = max(1, min(90, newValue)); persist(); if state == .idle, phase == .longBreak { remaining = duration(of: .longBreak) } }
    }
    /// Every fourth focus block earns the long break.
    public let blocksPerLongBreak = 4

    private let defaults: UserDefaults
    private var timer: Timer?
    private var lastTick: Date?
    private var completedOn: Date?
    /// Plays sounds and posts notifications; tests swap it for a recorder.
    var notify: @MainActor (Phase) -> Void = PomodoroModel.systemNotify

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let focus = defaults.integer(forKey: "pomodoro.focus"), brk = defaults.integer(forKey: "pomodoro.break"), long = defaults.integer(forKey: "pomodoro.long")
        self.focusStorage = focus > 0 ? focus : 25
        self.breakStorage = brk > 0 ? brk : 5
        self.longBreakStorage = long > 0 ? long : 15
        self.remaining = TimeInterval((focus > 0 ? focus : 25) * 60)
    }

    public var isRunning: Bool { state == .running }
    public var isActive: Bool { state != .idle }
    public var progress: Double { let total = duration(of: phase); return total > 0 ? 1 - remaining / total : 0 }
    public var display: String {
        let s = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    public func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(breakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    public func start() {
        guard state != .running else { return }
        if state == .idle { remaining = duration(of: phase) }
        state = .running
        lastTick = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func pause() {
        guard state == .running else { return }
        tick()
        state = .paused
        timer?.invalidate(); timer = nil
    }

    public func toggle() { isRunning ? pause() : start() }

    /// Back to the top of the current phase.
    public func reset() {
        timer?.invalidate(); timer = nil
        state = .idle
        remaining = duration(of: phase)
    }

    /// Jump to the next phase without finishing this one (no credit for a skipped focus).
    public func skip() {
        timer?.invalidate(); timer = nil
        state = .idle
        phase = phase == .focus ? nextBreak() : .focus
        remaining = duration(of: phase)
    }

    private func tick() {
        guard state == .running else { return }
        let now = Date()
        remaining -= now.timeIntervalSince(lastTick ?? now)
        lastTick = now
        if remaining <= 0 { finishPhase() }
    }

    /// Tests drive the clock directly.
    func advance(by seconds: TimeInterval) {
        guard state == .running else { return }
        remaining -= seconds
        lastTick = Date()
        if remaining <= 0 { finishPhase() }
    }

    private func finishPhase() {
        timer?.invalidate(); timer = nil
        let finished = phase
        if finished == .focus {
            rollDayIfNeeded()
            completedToday += 1
            completedOn = Date()
        }
        phase = finished == .focus ? nextBreak() : .focus
        state = .idle
        remaining = duration(of: phase)
        notify(finished)
    }

    private func nextBreak() -> Phase {
        completedToday > 0 && completedToday % blocksPerLongBreak == 0 ? .longBreak : .shortBreak
    }

    private func rollDayIfNeeded() {
        if let day = completedOn, !Calendar.current.isDateInToday(day) { completedToday = 0 }
    }

    private func persist() {
        defaults.set(focusMinutes, forKey: "pomodoro.focus")
        defaults.set(breakMinutes, forKey: "pomodoro.break")
        defaults.set(longBreakMinutes, forKey: "pomodoro.long")
    }

    // MARK: - Sound and notification

    private static var askedForNotifications = false

    static func systemNotify(_ finished: Phase) {
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = finished == .focus ? "Focus block done" : "Break over"
        content.body = finished == .focus ? "Nice. Take a break." : "Back to it."
        let center = UNUserNotificationCenter.current()
        let post = { center.add(UNNotificationRequest(identifier: "ante.pomodoro", content: content, trigger: nil)) }
        if askedForNotifications { post() } else {
            askedForNotifications = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in if granted { post() } }
        }
    }
}
