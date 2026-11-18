import Foundation
import XCTest
@testable import SupervimCore

/// The event tap has its own thread. Focus reports arrive on another queue,
/// hint results on a third, and the menu on the main thread. The interpreter
/// is the one object all of them touch.
final class EventInterpreterThreadingTests: XCTestCase {
    func testKeysFocusReportsAndHintEndsFromFourThreadsLeaveAUsableInterpreter() {
        let interpreter = EventInterpreter(settings: .defaults, clock: FixedClock(), cache: page)
        let rounds = 4_000
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "interpreter-stress", attributes: .concurrent)

        group.enter()
        queue.async {
            for index in 0..<rounds {
                let key: Character = index % 3 == 0 ? "f" : (index % 3 == 1 ? "g" : "j")
                _ = interpreter.handleKeyDown(KeyEvent(key), cache: index % 2 == 0 ? page : field)
                _ = interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: field)
            }
            group.leave()
        }
        group.enter()
        queue.async {
            for index in 0..<rounds {
                _ = interpreter.updateCache(index % 2 == 0 ? field : page)
                _ = interpreter.mode
            }
            group.leave()
        }
        group.enter()
        queue.async {
            for index in 0..<rounds {
                _ = interpreter.endHint(index % 2 == 0 ? .completed : .cancelled)
                _ = interpreter.acceptPointerClick(x: 20, y: 20)
                interpreter.releaseHeldInput()
            }
            group.leave()
        }
        group.enter()
        queue.async {
            for index in 0..<rounds {
                if index % 50 == 0 {
                    _ = interpreter.pause()
                    _ = interpreter.resume()
                }
                _ = interpreter.enterInsertAfterFocus()
                _ = interpreter.settingsSnapshot()
            }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)

        _ = interpreter.resume()
        _ = interpreter.updateCache(page)
        _ = interpreter.handleKeyDown(KeyEvent(identity: .escape), cache: page)
        _ = interpreter.updateCache(page)
        let decision = interpreter.handleKeyDown(KeyEvent("j"), cache: page)
        XCTAssertEqual(decision.delivery, .swallow)
        XCTAssertEqual(decision.actions, [CommandMap().action(for: .scrollDown)])
    }
}

private let page = CachedFocus(
    editability: .notEditable,
    bundleIdentifier: "com.apple.Safari",
    elementIdentity: "page",
    frame: FocusFrame(x: 0, y: 0, width: 400, height: 300),
    role: "AXWebArea"
)

private let field = CachedFocus(
    editability: .editable,
    bundleIdentifier: "com.apple.Safari",
    elementIdentity: "field",
    frame: FocusFrame(x: 0, y: 0, width: 200, height: 40),
    role: "AXTextField"
)

private final class FixedClock: KeyTimeSource, @unchecked Sendable {
    func nowMilliseconds() -> Int64 {
        1_000
    }
}
