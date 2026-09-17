import XCTest
@testable import AnteCore

final class RunEventBusTests: XCTestCase {
    func testSubscriberReceivesEventsInOrder() async {
        let bus = RunEventBus()
        let session = SessionID()
        let stream = bus.events()

        bus.publish(RunEvent(sessionID: session, event: .promptStarted))
        bus.publish(RunEvent(sessionID: session, event: .commandStarted))
        bus.publish(RunEvent(sessionID: session, event: .commandFinished(exitCode: 0)))

        var received: [SemanticEvent] = []
        for await e in stream {
            received.append(e.event)
            if received.count == 3 { break }
        }
        XCTAssertEqual(received, [.promptStarted, .commandStarted, .commandFinished(exitCode: 0)])
    }

    func testTwoSubscribersBothReceive() async {
        let bus = RunEventBus()
        let session = SessionID()
        let a = bus.events()
        let b = bus.events()
        XCTAssertEqual(bus.subscriberCount, 2)

        bus.publish(RunEvent(sessionID: session, event: .cwdChanged(URL(fileURLWithPath: "/tmp"))))

        var fromA: SemanticEvent?
        for await e in a { fromA = e.event; break }
        var fromB: SemanticEvent?
        for await e in b { fromB = e.event; break }
        XCTAssertEqual(fromA, .cwdChanged(URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(fromA, fromB)
    }

    func testCancelledSubscriberIsRemoved() async {
        let bus = RunEventBus()
        let task = Task {
            for await _ in bus.events() {}
        }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(bus.subscriberCount, 1)
        task.cancel()
        _ = await task.result
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(bus.subscriberCount, 0)
    }

    func testPublishWithNoSubscribersDoesNotCrash() {
        let bus = RunEventBus()
        bus.publish(RunEvent(sessionID: SessionID(), event: .promptStarted))
        XCTAssertEqual(bus.subscriberCount, 0)
    }
}
