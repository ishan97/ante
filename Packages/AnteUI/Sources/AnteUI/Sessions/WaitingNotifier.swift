// Packages/AnteUI/Sources/AnteUI/Sessions/WaitingNotifier.swift
import AppKit
import UserNotifications
import AnteCore

/// The "a session is waiting for you" notification: when it fires (pure rules, tested) and how
/// it is delivered (macOS notification plus a system sound the user picks in Settings).
public enum WaitingNotifier {
    public static let userInfoSessionKey = "ante.session"

    /// Cards that are in Waiting now and were not (or did not exist) a moment ago.
    static func newlyWaiting(previous: [SessionBoardModel.Card], next: [SessionBoardModel.Card]) -> [SessionBoardModel.Card] {
        let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.state.column) })
        return next.filter { $0.state.column == .waiting && before[$0.id] != .waiting }
    }

    /// Not for the pane the user is already looking at while Ante is in front.
    static func shouldNotify(card: SessionBoardModel.Card, focusedPane: PaneID?, appActive: Bool) -> Bool {
        !(appActive && focusedPane == card.id)
    }

    static func reason(for state: CardState, quietSeconds: Double) -> String {
        switch state {
        case let .waitingDefinite(reason): return reason
        case .waitingProbable: return "Quiet for \(Int(quietSeconds))s — probably waiting for you"
        case .working, .idle: return "Waiting for you"
        }
    }

    private enum Permission { case unknown, requesting, decided(Bool) }
    @MainActor private static var permission = Permission.unknown
    @MainActor private static var queued: [() -> Void] = []

    /// Posts the notification (silent: the sound is played here so the user's chosen system sound
    /// applies, which UNNotificationSound cannot do for /System/Library/Sounds) and tags it with
    /// the session so a click can focus it.
    @MainActor static func post(card: SessionBoardModel.Card, reason: String, sound: String) {
        SystemSounds.play(named: sound)
        let content = UNMutableNotificationContent()
        content.title = card.sessionName
        content.subtitle = card.agent.displayName
        content.body = reason
        content.userInfo = [userInfoSessionKey: card.sessionID.rawValue.uuidString]
        let center = UNUserNotificationCenter.current()
        let post = { center.add(UNNotificationRequest(identifier: "ante.waiting.\(card.id.rawValue.uuidString)", content: content, trigger: nil)) }
        switch permission {
        case .decided(true): post()
        case .decided(false): break
        case .requesting: queued.append(post)   // the prompt is still up; deliver once it is answered
        case .unknown:
            permission = .requesting
            queued.append(post)
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                Task { @MainActor in
                    permission = .decided(granted)
                    let pending = queued; queued = []
                    if granted { pending.forEach { $0() } }
                }
            }
        }
    }
}


/// macOS's own alert sounds, so the picker never needs files of its own.
public enum SystemSounds {
    public static let directory = URL(fileURLWithPath: "/System/Library/Sounds")

    /// "Basso", "Blow", … as found on this Mac, sorted.
    public static var names: [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "aiff" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    /// Plays a named system sound; an empty or unknown name plays nothing.
    public static func play(named name: String) {
        guard !name.isEmpty else { return }
        NSSound(named: name)?.play()
    }
}
