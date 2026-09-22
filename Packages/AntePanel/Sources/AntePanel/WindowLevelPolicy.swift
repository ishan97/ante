// Packages/AntePanel/Sources/AntePanel/WindowLevelPolicy.swift
import AppKit

/// Keeps secondary windows (Settings, alerts) above the workspace panel while the hotkey holds
/// it at a raised level, and puts back exactly the level each window had — a floating panel
/// such as the shared colour picker must stay floating afterwards.
public struct WindowLevelPolicy {
    private var lifted: [ObjectIdentifier: NSWindow.Level] = [:]

    public init() {}

    /// The level to give `window` so it sits above `panelLevel`, or nil when it already does
    /// (or was lifted before and not yet restored).
    public mutating func lift(_ window: NSWindow, over panelLevel: NSWindow.Level) -> NSWindow.Level? {
        let key = ObjectIdentifier(window)
        guard lifted[key] == nil, window.level.rawValue < panelLevel.rawValue else { return nil }
        lifted[key] = window.level
        return panelLevel
    }

    /// The level `window` had before it was lifted, or nil if this policy never touched it.
    public mutating func restore(_ window: NSWindow) -> NSWindow.Level? {
        lifted.removeValue(forKey: ObjectIdentifier(window))
    }
}

/// Which windows are in ⌘↩ full screen and the frame each one goes back to.
public struct FullScreenBookkeeping {
    private var restoreFrames: [ObjectIdentifier: CGRect] = [:]

    public init() {}

    public func isFullScreen(_ window: ObjectIdentifier) -> Bool { restoreFrames[window] != nil }

    public mutating func enter(_ window: ObjectIdentifier, restoring frame: CGRect) {
        if restoreFrames[window] == nil { restoreFrames[window] = frame }
    }

    /// The frame to restore, or nil when the window was not in full screen.
    public mutating func exit(_ window: ObjectIdentifier) -> CGRect? {
        restoreFrames.removeValue(forKey: window)
    }
}
