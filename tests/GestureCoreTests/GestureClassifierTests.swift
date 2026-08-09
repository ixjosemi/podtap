import XCTest

@testable import GestureCore

/// Threshold used across these tests. The press durations are taken from real
/// measurements on USB-C EarPods: taps of 79-231 ms, holds beyond 1700 ms.
private let threshold: Double = 0.3

private func down(_ at: Double) -> ButtonEvent {
    ButtonEvent(phase: .pressed, timestamp: at)
}

/// Not named `release`: that collides with the `NSObject` method `XCTestCase`
/// inherits.
private func up(_ at: Double) -> ButtonEvent {
    ButtonEvent(phase: .released, timestamp: at)
}

final class ShortTapTests: XCTestCase {
    func testShortTapEmitsPlayPauseOnRelease() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        XCTAssertEqual(classifier.handle(down(0)), [])
        XCTAssertEqual(classifier.handle(up(0.111)), [.emitPlayPause])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testLongestObservedTapIsStillATap() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        // 231 ms: the outlier captured during hardware probing.
        XCTAssertEqual(classifier.handle(up(0.231)), [.emitPlayPause])
    }

    func testConsecutiveTapsAreIndependent() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.handle(up(0.116)), [.emitPlayPause])

        _ = classifier.handle(down(1.5))
        XCTAssertEqual(classifier.handle(up(1.6)), [.emitPlayPause])
    }
}

final class HoldTests: XCTestCase {
    func testCrossingThresholdBeginsDictationWithoutWaitingForRelease() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.tick(at: 0.2), [])
        XCTAssertEqual(classifier.tick(at: 0.3), [.beginDictation])
        XCTAssertEqual(classifier.state, .dictating)
    }

    func testReleaseAfterHoldEndsDictationAndDoesNotEmitPlayPause() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        XCTAssertEqual(classifier.handle(up(1.947)), [.endDictation])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testRepeatedTicksDoNotRestartDictation() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.tick(at: 0.3), [.beginDictation])
        XCTAssertEqual(classifier.tick(at: 0.5), [])
        XCTAssertEqual(classifier.tick(at: 1.2), [])
    }

    func testTickWhileIdleIsInert() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        XCTAssertEqual(classifier.tick(at: 5), [])
        XCTAssertEqual(classifier.state, .idle)
    }
}

final class DegenerateInputTests: XCTestCase {
    func testOrphanReleaseIsIgnored() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        XCTAssertEqual(classifier.handle(up(0.5)), [])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testDuplicatePressDoesNotRestartTimer() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.handle(down(0.1)), [])
        // Had the second press restarted the timer, only 200 ms would have
        // elapsed at t=0.3 and dictation would not begin.
        XCTAssertEqual(classifier.tick(at: 0.3), [.beginDictation])
    }

    func testLateReleaseWithoutTickIsNotATap() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        // The tick never arrived (busy process, lazy clock). The duration says
        // plainly this was a hold; re-emitting play/pause would be wrong.
        XCTAssertNotEqual(classifier.handle(up(1.8)), [.emitPlayPause])
    }
}

final class InterruptTests: XCTestCase {
    func testInterruptDuringDictationReleasesKey() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        XCTAssertEqual(classifier.interrupt(), [.endDictation])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testInterruptWhilePressingEmitsNothing() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.interrupt(), [])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testInterruptWhileIdleIsInert() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        XCTAssertEqual(classifier.interrupt(), [])
        XCTAssertEqual(classifier.state, .idle)
    }
}
