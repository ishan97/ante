import Foundation

/// Fan-out of `RunEvent`s to any number of `AsyncStream` subscribers.
/// Thread-safe: `publish` may be called from any queue (the terminal's I/O queue in practice).
public final class RunEventBus: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<RunEvent>.Continuation] = [:]

    public init() {}

    public var subscriberCount: Int {
        lock.withLock { continuations.count }
    }

    public func publish(_ event: RunEvent) {
        let targets = lock.withLock { Array(continuations.values) }
        for continuation in targets {
            continuation.yield(event)
        }
    }

    /// A new subscription. Events published before this call are not delivered.
    public func events() -> AsyncStream<RunEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream(bufferingPolicy: .unbounded)
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
        }
        return stream
    }
}
