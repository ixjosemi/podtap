import Foundation
import IOKit
import IOKit.hid

public enum HIDInputError: LocalizedError {
    case inputMonitoringDenied
    case seizeFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case .inputMonitoringDenied:
            return "PodTap needs Input Monitoring permission to read the remote button."
        case .seizeFailed(let code):
            return "Could not take control of the device (IOReturn 0x\(String(code, radix: 16)))."
        }
    }
}

/// Physical button phase, mirrored here so `HIDInput` does not depend on
/// `GestureCore`: the input layer should know nothing about classification.
public enum ButtonTransition: Sendable, Equatable {
    case pressed
    case released
}

/// Opens the USB-C EarPods remote exclusively and publishes its presses.
///
/// Uses `kIOHIDOptionsTypeSeizeDevice`, which stops macOS from turning the
/// press into a play/pause. Re-emitting that, when appropriate, is the output
/// layer's job.
public final class EarPodsButtonMonitor {
    /// Apple USB-C EarPods.
    private static let vendorID = 0x05AC
    private static let productID = 0x110B
    /// HID Consumer Page and the button's specific usage.
    private static let consumerPage: UInt32 = 0x0C
    private static let consumerControlUsage = 0x01
    private static let playPauseUsage: UInt32 = 0x00CD

    /// Called on the main queue for every button transition, with a monotonic
    /// timestamp in seconds.
    public var onButton: ((ButtonTransition, TimeInterval) -> Void)?
    /// Called on the main queue when the EarPods are plugged or unplugged.
    public var onConnectionChange: ((Bool) -> Void)?

    public private(set) var isConnected = false

    private var manager: IOHIDManager?

    public init() {}

    deinit {
        stop()
    }

    /// Checks the permission without requesting it, so the interface can show
    /// status without triggering system dialogs.
    public static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Requests the permission, which surfaces the system dialog the first time.
    @discardableResult
    public static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public func start() throws {
        stop()

        // Deliberately no early return when access is missing. macOS only adds
        // an app to the Input Monitoring list once it has genuinely attempted
        // device access; bailing out beforehand means the user is left hunting
        // for PodTap under the "+" button because the system never heard of it.
        Self.requestInputMonitoringAccess()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match the specific Consumer interface rather than just vid/pid: the
        // EarPods also publish a vendor-defined interface whose seizure adds
        // nothing and whose side effects are unmeasured.
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey: Self.vendorID,
                kIOHIDProductIDKey: Self.productID,
                kIOHIDDeviceUsagePageKey: Int(Self.consumerPage),
                kIOHIDDeviceUsageKey: Self.consumerControlUsage,
            ] as CFDictionary
        )

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterInputValueCallback(manager, Self.valueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
            )
            // Missing permission is by far the likeliest cause, and it needs a
            // different message from a genuine device failure.
            throw Self.hasInputMonitoringAccess
                ? HIDInputError.seizeFailed(result)
                : HIDInputError.inputMonitoringDenied
        }

        self.manager = manager
        updateConnectionState(
            to: !((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.isEmpty ?? true)
        )
    }

    /// Hands the device back to the system. Idempotent.
    public func stop() {
        guard let manager else { return }
        self.manager = nil

        IOHIDManagerUnscheduleFromRunLoop(
            manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        updateConnectionState(to: false)
    }

    private func updateConnectionState(to connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onConnectionChange?(connected)
    }

    // MARK: - Bridges from the C callbacks

    private func receive(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == Self.consumerPage,
            IOHIDElementGetUsage(element) == Self.playPauseUsage
        else { return }

        let transition: ButtonTransition =
            IOHIDValueGetIntegerValue(value) == 1 ? .pressed : .released
        let timestamp = ProcessInfo.processInfo.systemUptime

        onButton?(transition, timestamp)
    }

    private static let valueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<EarPodsButtonMonitor>.fromOpaque(context).takeUnretainedValue()
            .receive(value: value)
    }

    private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<EarPodsButtonMonitor>.fromOpaque(context).takeUnretainedValue()
            .updateConnectionState(to: true)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<EarPodsButtonMonitor>.fromOpaque(context).takeUnretainedValue()
            .updateConnectionState(to: false)
    }
}
