import AppKit
import SwiftUI

/// Shared look: one accent, one corner scale, Liquid Glass on macOS 26+ with material fallbacks before.
/// Standard chrome (toolbar, sidebar, segmented pickers, forms) picks up Liquid Glass from the SDK on its own.
enum Theme {
    static let accent = Color.indigo
    /// Secondary text. A fixed opacity instead of `.secondary` keeps captions above WCAG AA
    /// (about 5.7:1 or better on light and dark surfaces; `.secondary` is about 4:1).
    static let muted = Color.primary.opacity(0.68)
    static let cardRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 12
    static let motion = Animation.smooth(duration: 0.25)
}

extension View {
    /// Frosted card for content sections. A material rather than Liquid Glass: Apple reserves glass for the
    /// control layer, and long text stays more readable on a calmer surface.
    func card(padding: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }

    /// Opaque text well (editors, results) so body text keeps full contrast.
    func field() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
        return self.background(Color(nsColor: .textBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
    }

    /// Liquid Glass surface on macOS 26+, thick material before.
    @ViewBuilder func glass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.thickMaterial, in: shape)
        }
    }

    /// Floating capsule controls: Liquid Glass buttons on macOS 26+, bordered capsules before.
    @ViewBuilder func capsuleButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
            else { self.buttonStyle(.bordered).buttonBorderShape(.capsule) }
        }
    }
}
