import XCTest

@testable import GestureCore

/// Umbral usado en todos los tests. Los tiempos de las pulsaciones están
/// tomados de mediciones reales sobre EarPods USB-C: toques de 79-231 ms,
/// mantenidos por encima de 1700 ms.
private let threshold: Double = 0.3

private func down(_ at: Double) -> ButtonEvent {
    ButtonEvent(phase: .pressed, timestamp: at)
}

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
        // 231 ms: el outlier real capturado en el spike sobre hardware.
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
        // Si la segunda pulsación hubiese reiniciado el cronómetro, en t=0.3
        // solo habrían pasado 200 ms y el dictado no arrancaría.
        XCTAssertEqual(classifier.tick(at: 0.3), [.beginDictation])
    }

    func testLateReleaseWithoutTickIsNotATap() {
        var classifier = GestureClassifier(holdThreshold: threshold)

        _ = classifier.handle(down(0))
        // El tick nunca llegó (proceso ocupado, reloj perezoso). La duración
        // dice que fue un mantenido: reemitir play/pause sería incorrecto.
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
