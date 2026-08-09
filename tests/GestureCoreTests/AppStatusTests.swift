import XCTest

@testable import GestureCore

private func status(
    enabled: Bool = true,
    connected: Bool = true,
    dictating: Bool = false
) -> AppStatus {
    AppStatus(isEnabled: enabled, isDeviceConnected: connected, isDictating: dictating)
}

final class AppStatusTests: XCTestCase {
    func testEnabledAndConnectedIsReady() {
        XCTAssertEqual(status(), .ready)
    }

    func testConnectedAndDictating() {
        XCTAssertEqual(status(dictating: true), .dictating)
    }

    func testEnabledWithoutEarPodsWaitsForTheDevice() {
        XCTAssertEqual(status(connected: false), .waitingForDevice)
    }

    func testDisabledOutranksEveryOtherSignal() {
        XCTAssertEqual(status(enabled: false), .disabled)
        XCTAssertEqual(status(enabled: false, connected: false), .disabled)
        XCTAssertEqual(status(enabled: false, dictating: true), .disabled)
    }

    /// Unplugging aborts the gesture, so this pairing should never arise. It is
    /// pinned anyway: a key that is still down matters more than a cable that
    /// is not, and reporting "no EarPods" would hide it.
    func testDictatingOutranksADisconnectedDevice() {
        XCTAssertEqual(status(connected: false, dictating: true), .dictating)
    }
}

final class AppStatusPresentationTests: XCTestCase {
    func testEveryStatusHasATitle() {
        for status in AppStatus.allCases {
            XCTAssertFalse(status.title.isEmpty, "\(status) has no title")
        }
    }

    func testOnlyDictatingIsToldToBeActive() {
        for status in AppStatus.allCases {
            XCTAssertEqual(status.isDictating, status == .dictating)
        }
    }

    func testTonesMatchTheSeverityOfTheState() {
        XCTAssertEqual(AppStatus.dictating.tone, .active)
        XCTAssertEqual(AppStatus.ready.tone, .positive)
        XCTAssertEqual(AppStatus.waitingForDevice.tone, .attention)
        XCTAssertEqual(AppStatus.disabled.tone, .neutral)
    }

    /// The menu bar icon is derived from the same value the settings window
    /// shows, so the two can never disagree about what PodTap is doing.
    func testEveryStatusHasASymbol() {
        for status in AppStatus.allCases {
            XCTAssertFalse(status.symbolName.isEmpty, "\(status) has no symbol")
        }
        XCTAssertEqual(AppStatus.dictating.symbolName, "waveform")
        XCTAssertEqual(AppStatus.ready.symbolName, "headphones")
    }

    func testSymbolsAreDistinctWhereTheStatesAre() {
        XCTAssertNotEqual(AppStatus.ready.symbolName, AppStatus.waitingForDevice.symbolName)
        XCTAssertNotEqual(AppStatus.ready.symbolName, AppStatus.disabled.symbolName)
    }
}
