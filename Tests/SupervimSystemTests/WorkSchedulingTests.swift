import Foundation
import XCTest
@testable import SupervimSystem

final class WorkSchedulingTests: XCTestCase {
    func testInlineWorkRunsBeforeReturning() {
        let log = Recorder()
        let work = InlineWork()
        work.run { log.add("a") }
        work.run(afterMilliseconds: 500) { log.add("b") }
        XCTAssertEqual(log.values, ["a", "b"])
    }

    func testManualWorkHoldsUntilReleasedAndKeepsOrder() {
        let log = Recorder()
        let work = ManualWork()
        work.run { log.add("a") }
        work.run(afterMilliseconds: 100) { log.add("late") }
        work.run {
            log.add("b")
            work.run { log.add("c") }
        }
        XCTAssertEqual(log.values, [])
        XCTAssertEqual(work.pending, 3)
        work.runPending()
        XCTAssertEqual(log.values, ["a", "b", "c"])
        work.advance(milliseconds: 99)
        XCTAssertEqual(log.values, ["a", "b", "c"])
        work.advance(milliseconds: 1)
        XCTAssertEqual(log.values, ["a", "b", "c", "late"])
        XCTAssertEqual(work.pending, 0)
    }

    func testQueueWorkRunsOffTheCallerInOrder() {
        let log = Recorder()
        let work = QueueWork(label: "supervim.test.queue")
        let gate = DispatchSemaphore(value: 0)
        work.run {
            gate.wait()
            log.add("a")
        }
        work.run { log.add("b") }
        work.run(afterMilliseconds: 5) { log.add("c") }
        XCTAssertEqual(log.values, [])
        gate.signal()
        work.drain()
        XCTAssertEqual(log.values, ["a", "b"])
        Thread.sleep(forTimeInterval: 0.05)
        work.drain()
        XCTAssertEqual(log.values, ["a", "b", "c"])
    }
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func add(_ value: String) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
