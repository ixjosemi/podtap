import CoreGraphics
import XCTest

@testable import KeyOutput

private let control = CGEventFlags.maskControl.rawValue
private let shift = CGEventFlags.maskShift.rawValue
private let option = CGEventFlags.maskAlternate.rawValue
private let command = CGEventFlags.maskCommand.rawValue
private let globe = CGEventFlags.maskSecondaryFn.rawValue

final class ShortcutRecordingTests: XCTestCase {
    private var recording = ShortcutRecording()

    override func setUp() {
        super.setUp()
        recording = ShortcutRecording()
    }

    // MARK: - Keys

    func testAPlainKeyCommitsImmediately() {
        let outcome = recording.handle(.keyDown(keyCode: 105, modifiers: 0))

        XCTAssertEqual(outcome, .committed(KeyCombination(keyCode: 105)))
    }

    func testAKeyCarriesItsModifiers() {
        let outcome = recording.handle(.keyDown(keyCode: 1, modifiers: command))

        XCTAssertEqual(outcome, .committed(KeyCombination(keyCode: 1, modifierFlags: command)))
    }

    func testEscapeAloneCancels() {
        XCTAssertEqual(recording.handle(.keyDown(keyCode: 53, modifiers: 0)), .cancelled)
    }

    func testEscapeWithModifiersIsARealShortcut() {
        let outcome = recording.handle(.keyDown(keyCode: 53, modifiers: command))

        XCTAssertEqual(outcome, .committed(KeyCombination(keyCode: 53, modifierFlags: command)))
    }

    func testGlobeIsStrippedFromKeyCombinations() {
        // macOS sets the Fn flag by itself on arrow and function keys, so a key
        // arriving with it is indistinguishable from one the user pressed while
        // holding Globe. Recording ← as 🌐← would be wrong far more often than
        // it would be right.
        let outcome = recording.handle(.keyDown(keyCode: 123, modifiers: globe | shift))

        XCTAssertEqual(outcome, .committed(KeyCombination(keyCode: 123, modifierFlags: shift)))
    }

    // MARK: - Modifier-only combinations

    func testASingleModifierCommitsOnRelease() {
        XCTAssertEqual(recording.handle(.modifiersChanged(control)), .recording)
        XCTAssertEqual(
            recording.handle(.modifiersChanged(0)),
            .committed(KeyCombination(keyCode: nil, modifierFlags: control))
        )
    }

    func testGlobeAloneIsRecordable() {
        XCTAssertEqual(recording.handle(.modifiersChanged(globe)), .recording)
        XCTAssertEqual(recording.handle(.modifiersChanged(0)), .committed(.globeOnly))
    }

    /// The regression that made ⌘⇧ save as ⌘. Modifiers are released one at a
    /// time, so the last non-zero report is a *subset* of what was held, never
    /// the whole combination.
    func testReleasingModifiersOneByOneKeepsThemAll() {
        XCTAssertEqual(recording.handle(.modifiersChanged(command)), .recording)
        XCTAssertEqual(recording.handle(.modifiersChanged(command | shift)), .recording)
        XCTAssertEqual(recording.handle(.modifiersChanged(command)), .recording)

        XCTAssertEqual(
            recording.handle(.modifiersChanged(0)),
            .committed(KeyCombination(keyCode: nil, modifierFlags: command | shift))
        )
    }

    func testReleasingInTheOppositeOrderRecordsTheSameCombination() {
        _ = recording.handle(.modifiersChanged(shift))
        _ = recording.handle(.modifiersChanged(shift | command))
        _ = recording.handle(.modifiersChanged(shift))

        XCTAssertEqual(
            recording.handle(.modifiersChanged(0)),
            .committed(KeyCombination(keyCode: nil, modifierFlags: command | shift))
        )
    }

    func testThreeModifiersSurviveAnyReleaseOrder() {
        _ = recording.handle(.modifiersChanged(control))
        _ = recording.handle(.modifiersChanged(control | option))
        _ = recording.handle(.modifiersChanged(control | option | shift))
        _ = recording.handle(.modifiersChanged(option | shift))
        _ = recording.handle(.modifiersChanged(shift))

        XCTAssertEqual(
            recording.handle(.modifiersChanged(0)),
            .committed(KeyCombination(keyCode: nil, modifierFlags: control | option | shift))
        )
    }

    func testUnsupportedModifiersNeverCommitAnything() {
        // Caps Lock is not offered, so a lone Caps Lock press must leave the
        // recorder waiting rather than store an empty combination.
        let capsLock = CGEventFlags.maskAlphaShift.rawValue

        XCTAssertEqual(recording.handle(.modifiersChanged(capsLock)), .recording)
        XCTAssertEqual(recording.handle(.modifiersChanged(0)), .recording)
    }

    func testAKeyPressedWhileModifiersAreHeldWinsOverThem() {
        _ = recording.handle(.modifiersChanged(command))

        XCTAssertEqual(
            recording.handle(.keyDown(keyCode: 1, modifiers: command)),
            .committed(KeyCombination(keyCode: 1, modifierFlags: command))
        )
    }

    func testHeldModifiersAreVisibleWhileRecording() {
        _ = recording.handle(.modifiersChanged(command))
        _ = recording.handle(.modifiersChanged(command | shift))

        XCTAssertEqual(recording.heldCombination.displayName, "⇧⌘")
    }

    func testNothingHeldHasNoCombination() {
        XCTAssertTrue(recording.heldCombination.isEmpty)
    }
}
