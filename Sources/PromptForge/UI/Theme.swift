import AppKit
import SwiftUI

/// Shared look. The accent comes from the AccentColor asset (Info.plist NSAccentColorName), so buttons,
/// selection and focus rings share one color and macOS still honors a user-chosen accent.
/// Standard chrome (toolbar, sidebar, pickers, forms, buttons) gets Liquid Glass from the SDK on its own.
enum Theme {
    /// Secondary text. A fixed opacity instead of `.secondary` keeps captions above WCAG AA
    /// (about 5.7:1 or better on light and dark surfaces; `.secondary` is about 4:1).
    static let muted = Color.primary.opacity(0.68)
    static let fieldRadius: CGFloat = 12
    static let motion = Animation.smooth(duration: 0.22)
}

extension View {
    /// Opaque text well (editors, results) so body text keeps full contrast.
    func field() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
        return self.background(Color(nsColor: .textBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
    }

    /// Animates layout changes keyed on `value`, or not at all when Reduce Motion is on.
    func motion<V: Equatable>(_ value: V) -> some View {
        modifier(MotionModifier(value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : Theme.motion, value: value)
    }
}
