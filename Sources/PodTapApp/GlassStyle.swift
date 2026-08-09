import AppKit
import GestureCore
import SwiftUI

/// The look shared by the settings window and the setup flow.
///
/// Two layers, and the order matters. `WindowBackdrop` is the only one that
/// samples the desktop, because only `NSVisualEffectView` can; SwiftUI's own
/// materials blur whatever is behind them *inside* the window, which over an
/// opaque window means blurring nothing. The cards then sit on that backdrop
/// and blur it in turn, which is where the depth comes from.

// MARK: - Window backdrop

/// Real vibrancy behind the whole window.
///
/// Only works if the window is non-opaque with a clear background — otherwise
/// AppKit paints over it and the result is a flat grey rectangle. See
/// `HostedWindowController`, which is what arranges that.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // `.underWindowBackground` is the material AppKit uses for windows that
        // want the desktop to show through, rather than the flatter one used
        // for sidebars.
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        // Keeps the blur alive when PodTap is not the frontmost app, which for
        // a background agent is most of the time.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Cards

/// A grouped box, the way System Settings draws one: material fill and a
/// hairline, and that is all.
///
/// It used to have a wide drop shadow and a white gradient rim along the top
/// edge. That is the house style of every glassmorphism template on the
/// internet, and it read as exactly that — a floating dashboard card rather
/// than a macOS control. The vibrancy is doing the work; the card only has to
/// group the rows sitting on it.
private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.strokeBorder(.primary.opacity(0.07), lineWidth: 1))
            .clipShape(shape)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

/// The name above a group. Sentence case and semibold, which is what macOS
/// uses — the tiny uppercase grey caption is an iOS idiom and looks borrowed
/// here.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.leading, 6)
    }
}

/// Divider between rows of the same card, inset so it stops short of the glass
/// edge rather than cutting the card in half.
struct RowDivider: View {
    var body: some View {
        Divider().opacity(0.5).padding(.leading, 16)
    }
}

// MARK: - Bundled artwork

/// GitHub's own mark, copied into the bundle by `build-app.sh`. There is no SF
/// Symbol for it, and a code-brackets glyph in its place is what the link falls
/// back to when the binary is run outside an app bundle.
///
/// Marked as a template so AppKit tints it with the current label colour, which
/// is what makes it follow light and dark mode.
enum Artwork {
    static let githubMark: Image = {
        guard let mark = NSImage(named: "GitHubMark") else {
            return Image(systemName: "chevron.left.forwardslash.chevron.right")
        }
        mark.isTemplate = true
        return Image(nsImage: mark)
    }()
}

// MARK: - Status

extension StatusTone {
    var color: Color {
        switch self {
        case .active: return .accentColor
        case .positive: return .green
        case .attention: return .orange
        case .neutral: return .secondary
        }
    }
}

/// Live state as a dot and the word for what it is doing. The dot breathes
/// while dictating, which is the one state worth spotting without reading.
///
/// No capsule around it: that made it a dashboard badge rather than the value
/// half of a settings row, which is what it actually is.
struct StatusIndicator: View {
    let status: AppStatus

    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.tone.color)
                .frame(width: 7, height: 7)
                .shadow(color: status.tone.color.opacity(0.7), radius: isBreathing ? 4 : 0)
                .opacity(isBreathing ? 0.45 : 1)

            Text(status.title)
                .foregroundStyle(.secondary)
        }
        .animation(breath, value: isBreathing)
        .onAppear { isBreathing = status.isDictating }
        .onChange(of: status) { _, new in isBreathing = new.isDictating }
    }

    private var breath: Animation? {
        status.isDictating
            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            : .easeOut(duration: 0.2)
    }
}
