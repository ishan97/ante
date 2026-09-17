// Packages/AnteUI/Sources/AnteUI/Runtime/UpdateChecking.swift
import Foundation

/// What the app's updater exposes to the UI. The real one wraps Sparkle in the app target;
/// tests and previews use a fake, and a nil updater hides every update control.
@MainActor
public protocol UpdateChecking: AnyObject {
    /// Sparkle's own preference: check the feed once a day without being asked.
    var automaticallyChecks: Bool { get set }
    /// False while a check or an install is already in progress.
    var canCheck: Bool { get }
    /// A user-initiated check: shows the result either way.
    func checkNow()
}
