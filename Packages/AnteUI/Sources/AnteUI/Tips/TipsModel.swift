// Packages/AnteUI/Sources/AnteUI/Tips/TipsModel.swift
import Foundation
import Observation

/// One thing worth knowing about Ante. `parts` mixes prose and key glyphs so keys can be drawn
/// as keys, and always shows the user's own bindings.
public struct Tip: Identifiable, Equatable, Sendable {
    public enum Part: Equatable, Sendable { case text(String), key(String) }

    public let id: String
    public let symbol: String
    public let parts: [Part]

    public init(id: String, symbol: String, _ parts: [Part]) {
        self.id = id
        self.symbol = symbol
        self.parts = parts
    }

    /// The tip as plain text, for VoiceOver and tests.
    public var plainText: String {
        parts.map { if case let .text(s) = $0 { return s } else if case let .key(k) = $0 { return k } else { return "" } }.joined()
    }
}

/// Decides when a tip appears and remembers what the user has seen. A tip comes at most every
/// few hours, each one at most `maxShows` times; "Don't show again" retires one for good, and
/// tips can be turned off altogether. Kept in UserDefaults, like the timer's lengths.
@MainActor
@Observable
public final class TipsModel {
    public static let maxShows = 5
    /// The least time between two tips.
    public static let spacing: TimeInterval = 3 * 3600

    /// The tip on screen, if any.
    public private(set) var current: Tip?
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled { current = nil }
        }
    }
    public private(set) var shows: [String: Int]
    public private(set) var hidden: Set<String>
    public private(set) var lastShownAt: Date?

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "tips.enabled", shows = "tips.shows", hidden = "tips.hidden", last = "tips.lastShownAt"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        shows = (defaults.dictionary(forKey: Keys.shows) as? [String: Int]) ?? [:]
        hidden = Set(defaults.stringArray(forKey: Keys.hidden) ?? [])
        let last = defaults.double(forKey: Keys.last)
        lastShownAt = last > 0 ? Date(timeIntervalSince1970: last) : nil
    }

    /// The tip that would come next: among those not retired and shown fewer than `maxShows`
    /// times, the least seen, in catalogue order.
    public func next(from catalogue: [Tip]) -> Tip? {
        let eligible = catalogue.filter { !hidden.contains($0.id) && shows[$0.id, default: 0] < Self.maxShows }
        return eligible.min { shows[$0.id, default: 0] < shows[$1.id, default: 0] }
    }

    /// Shows the next tip if tips are on, none is showing, and the last one was long enough ago.
    @discardableResult
    public func presentIfDue(_ catalogue: [Tip], now: Date = Date()) -> Bool {
        guard isEnabled, current == nil else { return false }
        if let lastShownAt, now.timeIntervalSince(lastShownAt) < Self.spacing, now >= lastShownAt { return false }
        guard let tip = next(from: catalogue) else { return false }
        current = tip
        shows[tip.id, default: 0] += 1
        lastShownAt = now
        save()
        return true
    }

    /// Puts the tip away; it may come back another time (up to `maxShows`).
    public func close() {
        current = nil
    }

    /// Retires the tip on screen for good.
    public func hideCurrentForever() {
        guard let tip = current else { return }
        hidden.insert(tip.id)
        current = nil
        save()
    }

    /// Every tip is fresh again, and tips are on.
    public func reset() {
        shows = [:]
        hidden = []
        lastShownAt = nil
        isEnabled = true
        save()
    }

    private func save() {
        defaults.set(shows, forKey: Keys.shows)
        defaults.set(hidden.sorted(), forKey: Keys.hidden)
        if let lastShownAt { defaults.set(lastShownAt.timeIntervalSince1970, forKey: Keys.last) } else { defaults.removeObject(forKey: Keys.last) }
    }
}
