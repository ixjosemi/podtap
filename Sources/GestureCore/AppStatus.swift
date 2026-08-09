/// What PodTap is doing right now, as one value.
///
/// The menu bar icon and the settings window both read from this, so they
/// cannot end up describing different things. It lives here rather than in the
/// app because it is pure: four booleans in, one case out, no frameworks and
/// nothing to mock.
public enum AppStatus: Sendable, Equatable, CaseIterable {
    /// Turned off by the user. PodTap holds no device and sends nothing.
    case disabled
    /// A key is down and the dictation app is listening.
    case dictating
    /// Enabled, but no EarPods are plugged in.
    case waitingForDevice
    /// Enabled, connected, waiting for a press.
    case ready

    /// Precedence, highest first: the user's own switch, then a key that is
    /// still held, then the cable, then the happy path. Dictating outranks the
    /// device being gone because a stranded key is the more useful thing to
    /// show — though the classifier's interrupt means it should never happen.
    public init(isEnabled: Bool, isDeviceConnected: Bool, isDictating: Bool) {
        if !isEnabled {
            self = .disabled
        } else if isDictating {
            self = .dictating
        } else if !isDeviceConnected {
            self = .waitingForDevice
        } else {
            self = .ready
        }
    }

    public var isDictating: Bool { self == .dictating }

    public var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .dictating: return "Dictating"
        case .waitingForDevice: return "No EarPods"
        case .ready: return "Ready"
        }
    }

    /// SF Symbol name. A plain string, so naming it here costs `GestureCore`
    /// no dependency on any framework.
    public var symbolName: String {
        switch self {
        case .disabled: return "headphones.slash"
        case .dictating: return "waveform"
        case .waitingForDevice: return "cable.connector.slash"
        case .ready: return "headphones"
        }
    }

    /// How loudly the interface should say it. Mapping a tone to an actual
    /// colour is the view's business.
    public var tone: StatusTone {
        switch self {
        case .disabled: return .neutral
        case .dictating: return .active
        case .waitingForDevice: return .attention
        case .ready: return .positive
        }
    }
}

public enum StatusTone: Sendable, Equatable {
    /// Something is happening right now.
    case active
    /// Working as intended.
    case positive
    /// Needs the user to do something.
    case attention
    /// Off, and deliberately so.
    case neutral
}
