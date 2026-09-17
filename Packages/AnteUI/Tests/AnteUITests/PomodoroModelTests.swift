// Packages/AnteUI/Tests/AnteUITests/PomodoroModelTests.swift
import XCTest
@testable import AnteUI

@MainActor
final class PomodoroModelTests: XCTestCase {
    private func makeModel() -> (PomodoroModel, () -> [PomodoroModel.Phase]) {
        let defaults = UserDefaults(suiteName: "ante-pomodoro-tests-\(UUID().uuidString)")!
        let model = PomodoroModel(defaults: defaults)
        var finished: [PomodoroModel.Phase] = []
        model.notify = { finished.append($0) }
        return (model, { finished })
    }

    func testFocusThenBreakThenLongBreakAfterFour() {
        let (m, finished) = makeModel()
        XCTAssertEqual(m.display, "25:00")
        XCTAssertEqual(m.state, .idle)
        for block in 1...4 {
            m.start()
            m.advance(by: 25 * 60)
            XCTAssertEqual(m.completedToday, block)
            XCTAssertEqual(m.phase, block == 4 ? .longBreak : .shortBreak, "the fourth block earns the long break")
            XCTAssertEqual(m.state, .idle, "phases do not auto-start")
            m.start(); m.advance(by: m.duration(of: m.phase))
            XCTAssertEqual(m.phase, .focus)
        }
        XCTAssertEqual(finished().count, 8)
        XCTAssertEqual(finished().first, .focus)
    }

    func testPauseResumeResetAndSkip() {
        let (m, finished) = makeModel()
        m.start(); m.advance(by: 60)
        m.pause()
        XCTAssertEqual(m.state, .paused)
        XCTAssertEqual(m.display, "24:00")
        m.advance(by: 600)
        XCTAssertEqual(m.display, "24:00", "a paused timer does not move")
        m.start(); XCTAssertEqual(m.state, .running)
        m.reset()
        XCTAssertEqual(m.state, .idle); XCTAssertEqual(m.display, "25:00")
        m.skip()
        XCTAssertEqual(m.phase, .shortBreak); XCTAssertEqual(m.display, "05:00")
        XCTAssertEqual(m.completedToday, 0, "skipping earns nothing")
        XCTAssertTrue(finished().isEmpty)
    }

    func testDurationsAreClampedAndRemembered() {
        let defaults = UserDefaults(suiteName: "ante-pomodoro-tests-\(UUID().uuidString)")!
        let m = PomodoroModel(defaults: defaults)
        m.focusMinutes = 500; XCTAssertEqual(m.focusMinutes, 120); XCTAssertEqual(m.display, "120:00")
        m.breakMinutes = 0; XCTAssertEqual(m.breakMinutes, 1)
        XCTAssertEqual(PomodoroModel(defaults: defaults).focusMinutes, 120)
    }
}

@MainActor
final class DurationFieldTests: XCTestCase {
    func testTypedMinutesAreClampedAndInvalidTextKeepsTheOldValue() {
        XCTAssertEqual(DurationField.parse("40", in: 1...120, fallback: 25), 40)
        XCTAssertEqual(DurationField.parse(" 7 ", in: 1...60, fallback: 5), 7)
        XCTAssertEqual(DurationField.parse("500", in: 1...90, fallback: 15), 90)
        XCTAssertEqual(DurationField.parse("0", in: 1...120, fallback: 25), 1)
        XCTAssertEqual(DurationField.parse("-3", in: 1...120, fallback: 25), 1)
        XCTAssertEqual(DurationField.parse("abc", in: 1...120, fallback: 25), 25)
        XCTAssertEqual(DurationField.parse("1.5", in: 1...120, fallback: 25), 25)
        XCTAssertEqual(DurationField.parse("", in: 1...120, fallback: 25), 25)
    }
}
