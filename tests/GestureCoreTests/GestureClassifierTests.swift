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

/// The latch is not a preference, it is what the hardware allows. USB-C EarPods
/// mute their microphone for as long as the remote button is held: measured over
/// two seconds of continuous speech, 88 200 consecutive samples of digital
/// silence, every one exactly zero. Dictation therefore has to happen with the
/// button *free*, so the key stays down on its own until a closing tap.
final class LatchTests: XCTestCase {
    func testCrossingThresholdBeginsDictationWithoutWaitingForRelease() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.tick(at: 0.2), [])
        XCTAssertEqual(classifier.tick(at: 0.3), [.beginDictation])
        XCTAssertEqual(classifier.state, .dictating)
    }

    func testReleasingTheButtonLeavesTheKeyLatched() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)

        // Letting go is what un-mutes the microphone, so it must not end
        // anything.
        XCTAssertEqual(classifier.handle(up(0.5)), [])
        XCTAssertEqual(classifier.state, .dictating)
    }

    func testTheNextPressEndsDictation() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))

        XCTAssertEqual(classifier.handle(down(6.0)), [.endDictation])
    }

    func testTheClosingTapDoesNotAlsoEmitPlayPause() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))
        _ = classifier.handle(down(6.0))

        // Short enough to look exactly like a tap, and it must not be one.
        XCTAssertEqual(classifier.handle(up(6.1)), [])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testATapAfterClosingIsAnOrdinaryPlayPauseAgain() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))
        _ = classifier.handle(down(6.0))
        _ = classifier.handle(up(6.1))

        _ = classifier.handle(down(8.0))
        XCTAssertEqual(classifier.handle(up(8.1)), [.emitPlayPause])
    }

    func testHoldingThroughTheWholeGestureStillLatches() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        // A long hold with no tick in between: the duration alone must be
        // enough to arm the latch, or the gesture silently does nothing.
        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.handle(up(1.8)), [.beginDictation])
        XCTAssertEqual(classifier.state, .dictating)
    }

    func testRepeatedTicksDoNotRestartDictation() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        XCTAssertEqual(classifier.tick(at: 0.3), [.beginDictation])
        XCTAssertEqual(classifier.tick(at: 0.5), [])
        XCTAssertEqual(classifier.tick(at: 1.2), [])
    }

    func testTickWhileClosingIsInert() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))
        _ = classifier.handle(down(6.0))

        // Holding the closing press past the threshold must not open a second
        // dictation on the way out.
        XCTAssertEqual(classifier.tick(at: 6.5), [])
        XCTAssertEqual(classifier.state, .closing)
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

    func testChatterWhileLatchedDoesNotCloseTwice() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))

        XCTAssertEqual(classifier.handle(down(6.0)), [.endDictation])
        XCTAssertEqual(classifier.handle(down(6.02)), [])
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

    /// The latch outlives the button, so unplugging mid-dictation is the case
    /// that would otherwise leave a key held down with nothing able to lift it.
    func testInterruptAfterTheButtonIsReleasedStillReleasesTheKey() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))

        XCTAssertEqual(classifier.interrupt(), [.endDictation])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testInterruptWhileClosingEmitsNothing() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        _ = classifier.tick(at: 0.3)
        _ = classifier.handle(up(0.5))
        _ = classifier.handle(down(6.0))

        // The key came up with the closing press; releasing it twice would
        // leave the dictation app with an unmatched key-up.
        XCTAssertEqual(classifier.interrupt(), [])
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
