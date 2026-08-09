import XCTest

@testable import GestureCore

private func down(_ at: Double) -> ButtonEvent {
    ButtonEvent(phase: .pressed, timestamp: at)
}

/// Not named `release`: that collides with the `NSObject` method `XCTestCase`
/// inherits.
private func up(_ at: Double) -> ButtonEvent {
    ButtonEvent(phase: .released, timestamp: at)
}

final class ToggleTests: XCTestCase {
    func testAPressStartsDictationImmediately() {
        var classifier = GestureClassifier()

        XCTAssertEqual(classifier.handle(down(0)), [.beginDictation])
        XCTAssertEqual(classifier.state, .opening)
    }

    func testLettingGoDoesNotStopIt() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))

        // Letting go is what un-mutes the microphone, so it must change
        // nothing: the key stays down.
        XCTAssertEqual(classifier.handle(up(0.1)), [])
        XCTAssertEqual(classifier.state, .dictating)
    }

    func testTheNextPressStopsIt() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))
        _ = classifier.handle(up(0.1))

        XCTAssertEqual(classifier.handle(down(6.0)), [.endDictation])
        XCTAssertEqual(classifier.state, .closing)
    }

    func testReleasingTheClosingPressReturnsToIdle() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))
        _ = classifier.handle(up(0.1))
        _ = classifier.handle(down(6.0))

        XCTAssertEqual(classifier.handle(up(6.1)), [])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testTheCycleRepeats() {
        var classifier = GestureClassifier()

        for round in 0..<3 {
            let t = Double(round) * 10
            XCTAssertEqual(classifier.handle(down(t)), [.beginDictation])
            XCTAssertEqual(classifier.handle(up(t + 0.1)), [])
            XCTAssertEqual(classifier.handle(down(t + 5)), [.endDictation])
            XCTAssertEqual(classifier.handle(up(t + 5.1)), [])
            XCTAssertEqual(classifier.state, .idle)
        }
    }

    func testDurationIsIrrelevant() {
        var classifier = GestureClassifier()

        // A long press is the same gesture as a short one. Nothing measures
        // time any more, so holding the button simply delays the microphone
        // coming back.
        XCTAssertEqual(classifier.handle(down(0)), [.beginDictation])
        XCTAssertEqual(classifier.handle(up(4.0)), [])
        XCTAssertEqual(classifier.state, .dictating)
    }
}

final class DegenerateInputTests: XCTestCase {
    func testOrphanReleaseIsIgnored() {
        var classifier = GestureClassifier()

        XCTAssertEqual(classifier.handle(up(0.5)), [])
        XCTAssertEqual(classifier.state, .idle)
    }

    /// The failure this guards against is the worst one available: a repeated
    /// press with no release between would start and immediately stop, so the
    /// button would look dead.
    func testChatterOnTheOpeningPressDoesNotStopDictation() {
        var classifier = GestureClassifier()

        XCTAssertEqual(classifier.handle(down(0)), [.beginDictation])
        XCTAssertEqual(classifier.handle(down(0.02)), [])
        XCTAssertEqual(classifier.state, .opening)
    }

    func testChatterOnTheClosingPressDoesNotRestartDictation() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))
        _ = classifier.handle(up(0.1))

        XCTAssertEqual(classifier.handle(down(6.0)), [.endDictation])
        XCTAssertEqual(classifier.handle(down(6.02)), [])
        XCTAssertEqual(classifier.state, .closing)
    }

    func testOrphanReleaseWhileDictatingIsIgnored() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))
        _ = classifier.handle(up(0.1))

        XCTAssertEqual(classifier.handle(up(0.2)), [])
        XCTAssertEqual(classifier.state, .dictating)
    }
}

final class InterruptTests: XCTestCase {
    func testInterruptWhileTheOpeningPressIsStillDownReleasesKey() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))

        XCTAssertEqual(classifier.interrupt(), [.endDictation])
        XCTAssertEqual(classifier.state, .idle)
    }

    /// The latch outlives the button, so unplugging mid-dictation is the case
    /// that would otherwise leave a key held down with nothing able to lift it.
    func testInterruptWhileLatchedReleasesKey() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))
        _ = classifier.handle(up(0.1))

        XCTAssertEqual(classifier.interrupt(), [.endDictation])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testInterruptWhileClosingEmitsNothing() {
        var classifier = GestureClassifier()

        _ = classifier.handle(down(0))
        _ = classifier.handle(up(0.1))
        _ = classifier.handle(down(6.0))

        // The key came up with the closing press; releasing it twice would
        // leave the dictation app with an unmatched key-up.
        XCTAssertEqual(classifier.interrupt(), [])
        XCTAssertEqual(classifier.state, .idle)
    }

    func testInterruptWhileIdleIsInert() {
        var classifier = GestureClassifier()

        XCTAssertEqual(classifier.interrupt(), [])
        XCTAssertEqual(classifier.state, .idle)
    }
}
