import Foundation

/// A `SemanticEvent` stamped with which session it came from and when.
public struct RunEvent: Equatable, Sendable {
    public let sessionID: SessionID
    public let event: SemanticEvent
    public let at: Date

    public init(sessionID: SessionID, event: SemanticEvent, at: Date = Date()) {
        self.sessionID = sessionID
        self.event = event
        self.at = at
    }
}
