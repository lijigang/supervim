import Foundation
import XCTest
@testable import SupervimCore

/// The debug log is written from the event hook's thread, so a line must cost
/// a lock and an enqueue, not a file open and a defaults lookup.
final class ModeTraceTests: XCTestCase {
    func testTimingLineNamesTheStageAndRoundsToATenth() {
        XCTAssertEqual(
            ModeTrace.formatTiming(stage: "hint-scan", milliseconds: 41.26, fields: [("nodes", "350"), ("hits", "42")]),
            "timing stage=hint-scan ms=41.3 nodes=350 hits=42"
        )
        XCTAssertEqual(
            ModeTrace.formatTiming(stage: "tap", milliseconds: 0.04, fields: []),
            "timing stage=tap ms=0.0"
        )
        XCTAssertEqual(
            ModeTrace.formatTiming(stage: "tap", milliseconds: .nan, fields: []),
            "timing stage=tap ms=-"
        )
    }

    func testCaptureCollectsLinesAndRestoresThePreviousState() {
        let lines = ModeTrace.capture {
            ModeTrace.noteLine("first")
            ModeTrace.noteTiming(stage: "overlay", milliseconds: 3, fields: [("labels", "12")])
        }
        XCTAssertEqual(lines, ["first", "timing stage=overlay ms=3.0 labels=12"])
        let later = ModeTrace.capture {
            ModeTrace.noteLine("second")
        }
        XCTAssertEqual(later, ["second"])
    }

    func testStopwatchMeasuresElapsedMilliseconds() {
        let watch = TraceStopwatch()
        Thread.sleep(forTimeInterval: 0.02)
        let elapsed = watch.milliseconds
        XCTAssertGreaterThanOrEqual(elapsed, 15)
        XCTAssertLessThan(elapsed, 2_000)
    }

    func testSwitchAsksTheProbeOncePerInterval() {
        let clock = SwitchClock()
        let probes = ProbeCount()
        let toggle = TraceSwitch(intervalMilliseconds: 2_000, now: { clock.now }) {
            probes.bump()
            return true
        }
        for _ in 0..<1_000 {
            XCTAssertTrue(toggle.isOn())
        }
        XCTAssertEqual(probes.count, 1)
        clock.now += 1_999
        XCTAssertTrue(toggle.isOn())
        XCTAssertEqual(probes.count, 1)
        clock.now += 2
        XCTAssertTrue(toggle.isOn())
        XCTAssertEqual(probes.count, 2)
    }

    func testSwitchFollowsTheProbeAfterTheIntervalPasses() {
        let clock = SwitchClock()
        let answer = ProbeAnswer()
        let toggle = TraceSwitch(intervalMilliseconds: 100, now: { clock.now }) {
            answer.value
        }
        XCTAssertFalse(toggle.isOn())
        answer.value = true
        XCTAssertFalse(toggle.isOn())
        clock.now += 101
        XCTAssertTrue(toggle.isOn())
    }

    func testWriterAppendsInOrderThroughOneHandle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervim-trace-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("nested/Supervim.log", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = TraceFileWriter(url: url)
        for index in 0..<200 {
            writer.write("line \(index)")
        }
        writer.flush()
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 200)
        XCTAssertEqual(lines.first, "line 0")
        XCTAssertEqual(lines.last, "line 199")
        XCTAssertEqual(writer.opens, 1)

        let second = TraceFileWriter(url: url)
        second.write("appended")
        second.flush()
        let grown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(grown.hasSuffix("line 199\nappended\n"))
    }

    func testWriterDoesNotBlockTheCallerOnTheDisk() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervim-trace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = TraceFileWriter(url: directory.appendingPathComponent("Supervim.log"))
        let gate = DispatchSemaphore(value: 0)
        writer.hold(gate)
        let watch = TraceStopwatch()
        for index in 0..<500 {
            writer.write("held \(index)")
        }
        let enqueue = watch.milliseconds
        gate.signal()
        writer.flush()
        XCTAssertLessThan(enqueue, 200)
    }

    func testWriterThatCannotOpenTheFileDropsLines() {
        let writer = TraceFileWriter(url: URL(fileURLWithPath: "/dev/null/not-a-directory/Supervim.log"))
        writer.write("lost")
        writer.flush()
        XCTAssertEqual(writer.opens, 0)
    }
}

private final class SwitchClock: @unchecked Sendable {
    var now: Int64 = 10_000
}

private final class ProbeCount: @unchecked Sendable {
    private(set) var count = 0

    func bump() {
        count += 1
    }
}

private final class ProbeAnswer: @unchecked Sendable {
    var value = false
}
