import CoreGraphics
import XCTest

@testable import KeyOutput

final class KeyCombinationTests: XCTestCase {
    func testDefaultIsF13() {
        XCTAssertEqual(KeyCombination.defaultCombination.displayName, "F13")
    }

    func testModifiersRenderInCanonicalOrder() {
        let combination = KeyCombination(
            keyCode: 49,
            modifierFlags: CGEventFlags.maskCommand.rawValue
                | CGEventFlags.maskControl.rawValue
                | CGEventFlags.maskShift.rawValue
                | CGEventFlags.maskAlternate.rawValue
        )

        XCTAssertEqual(combination.displayName, "⌃⌥⇧⌘Space")
    }

    func testUnsupportedModifiersAreDiscarded() {
        // Caps Lock and Fn are not valid shortcut modifiers and must not end up
        // stored in the configuration.
        let combination = KeyCombination(
            keyCode: 0,
            modifierFlags: CGEventFlags.maskAlphaShift.rawValue
                | CGEventFlags.maskSecondaryFn.rawValue
                | CGEventFlags.maskCommand.rawValue
        )

        XCTAssertEqual(combination.displayName, "⌘A")
    }

    func testUnknownKeyCodeFallsBackToItsNumber() {
        XCTAssertEqual(KeyCombination(keyCode: 200).displayName, "Key 200")
    }

    func testRoundTripsThroughJSON() throws {
        let original = KeyCombination(
            keyCode: 105, modifierFlags: CGEventFlags.maskShift.rawValue)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombination.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
