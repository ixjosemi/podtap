import CoreGraphics
import XCTest

@testable import KeyOutput

private let control = CGEventFlags.maskControl.rawValue
private let shift = CGEventFlags.maskShift.rawValue
private let option = CGEventFlags.maskAlternate.rawValue
private let command = CGEventFlags.maskCommand.rawValue
private let globe = CGEventFlags.maskSecondaryFn.rawValue

final class KeyCombinationTests: XCTestCase {
    func testDefaultIsF13() {
        XCTAssertEqual(KeyCombination.defaultCombination.displayName, "F13")
    }

    func testModifiersRenderInCanonicalOrder() {
        let combination = KeyCombination(
            keyCode: 49,
            modifierFlags: command | control | shift | option
        )

        XCTAssertEqual(combination.displayName, "⌃⌥⇧⌘Space")
    }

    func testUnsupportedModifiersAreDiscarded() {
        // Caps Lock latches rather than being held, so it cannot drive a
        // press-and-hold trigger and must not reach the configuration.
        let combination = KeyCombination(
            keyCode: 0,
            modifierFlags: CGEventFlags.maskAlphaShift.rawValue | command
        )

        XCTAssertEqual(combination.displayName, "⌘A")
    }

    func testUnknownKeyCodeFallsBackToItsNumber() {
        XCTAssertEqual(KeyCombination(keyCode: 200).displayName, "Key 200")
    }

    func testRoundTripsThroughJSON() throws {
        let original = KeyCombination(keyCode: 105, modifierFlags: shift)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombination.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

final class ModifierOnlyCombinationTests: XCTestCase {
    func testGlobeAloneIsAValidCombination() {
        let fn = KeyCombination.globeOnly

        XCTAssertTrue(fn.isModifiersOnly)
        XCTAssertFalse(fn.isEmpty)
        XCTAssertEqual(fn.displayName, "🌐")
    }

    func testControlShiftIsAValidCombination() {
        let combination = KeyCombination(keyCode: nil, modifierFlags: control | shift)

        XCTAssertTrue(combination.isModifiersOnly)
        XCTAssertEqual(combination.displayName, "⌃⇧")
    }

    func testOptionShiftIsAValidCombination() {
        let combination = KeyCombination(keyCode: nil, modifierFlags: option | shift)

        XCTAssertEqual(combination.displayName, "⌥⇧")
    }

    func testGlobeLeadsTheOtherModifiers() {
        let combination = KeyCombination(keyCode: nil, modifierFlags: command | globe)

        XCTAssertEqual(combination.displayName, "🌐⌘")
    }

    func testNothingHeldIsEmpty() {
        let combination = KeyCombination(keyCode: nil, modifierFlags: 0)

        XCTAssertTrue(combination.isEmpty)
        XCTAssertFalse(combination.isModifiersOnly)
        XCTAssertEqual(combination.displayName, "None")
    }

    func testAKeyWithModifiersIsNotModifiersOnly() {
        XCTAssertFalse(KeyCombination(keyCode: 1, modifierFlags: command).isModifiersOnly)
    }

    func testModifierOnlyCombinationRoundTripsThroughJSON() throws {
        let original = KeyCombination(keyCode: nil, modifierFlags: control | shift)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombination.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.keyCode)
    }
}

final class ModifierKeyCodeTests: XCTestCase {
    func testEverySupportedModifierHasAKeyCode() {
        // Emitting a modifier-only combination means sending one transition per
        // modifier, so a missing key code would silently drop that modifier.
        let mapped = KeyCombination.modifierKeyCodes.reduce(UInt64(0)) {
            $0 | $1.flag.rawValue
        }

        XCTAssertEqual(mapped, KeyCombination.supportedModifiers)
    }

    func testModifierKeyCodesAreDistinct() {
        let codes = KeyCombination.modifierKeyCodes.map(\.keyCode)

        XCTAssertEqual(Set(codes).count, codes.count)
    }
}
