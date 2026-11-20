import AppKit
import SwiftUI

/// Hone's look, adopted from the Dial reference (direction contract: .impeccable/surfaces/):
/// cool graphite grounds (mist in light mode), a lighter tone for text wells, hairline-ruled sections,
/// periwinkle markers, and one accent (AccentColor asset) for selection and each area's primary action.
/// Controls and navigation stay native; the signature move is `ScoreMeter`.
enum Theme {
    static let ground = dynamic(light: 0xF4F5F9, dark: 0x1F1F23)
    /// Second neutral layer, for the output side.
    static let groundAlt = dynamic(light: 0xECEEF4, dark: 0x26262B)
    /// Result wells: the brightest surface on screen.
    static let fieldFill = dynamic(light: 0xFFFFFF, dark: 0x2E2E34)
    /// Input wells, one step quieter than results.
    static let inputFill = dynamic(light: 0xF1F2F6, dark: 0x27272C)
    static let track = dynamic(light: 0xD9DCE5, dark: 0x3A3A41)
    static let hairline = Color.primary.opacity(0.09)
    /// Periwinkle markers (list dots, header dot). Decorative, never text.
    static let dot = dynamic(light: 0x7C89F5, dark: 0x8997FC)
    /// Secondary text. A fixed opacity instead of `.secondary` keeps captions above WCAG AA:
    /// primary is labelColor (85% alpha), so this lands near #5B5B5B on mist and #ACACAC on graphite,
    /// about 5.8:1 or better on every ground here (`.secondary` is about 4:1).
    static let muted = Color.primary.opacity(0.74)
    static let fieldRadius: CGFloat = 12
    static let motion = Animation.smooth(duration: 0.22)
    /// Dial's sunrise, spread across the whole 0–100 range so a higher score reaches warmer light.
    static let sunrise = Gradient(stops: [
        .init(color: dynamic(light: 0xD6E4F6, dark: 0xEEF1F7), location: 0),
        .init(color: rgb(0xC5E3FB), location: 0.22),
        .init(color: rgb(0x86C3F9), location: 0.42),
        .init(color: rgb(0xF6D35A), location: 0.64),
        .init(color: rgb(0xF4B04F), location: 0.82),
        .init(color: rgb(0xF08C4B), location: 1),
    ])

    private static func rgb(_ hex: UInt32) -> Color { Color(nsColor: nsColor(hex)) }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

extension View {
    /// Text well; results use the default bright fill, inputs pass `Theme.inputFill`.
    func field(_ fill: Color = Theme.fieldFill) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
        return self.background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    /// macOS draws text-field placeholders in a grey below WCAG AA and ignores styling them,
    /// so the hint is drawn in `Theme.muted` over an empty field instead.
    func placeholder(_ text: String, when isEmpty: Bool) -> some View {
        overlay(alignment: .leading) {
            if isEmpty {
                Text(text).foregroundStyle(Theme.muted).lineLimit(1)
                    .padding(.leading, 6).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
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

/// Section rule: the hairline between Dial-style sections.
struct SectionRule: View {
    var body: some View { Divider().padding(.vertical, 18) }
}

/// A Dial row: muted label on the left, its value or control on the right.
struct OptionRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            content
        }
    }
}

/// Hone's signature: the prompt score as Dial's sunrise track. While the model works the track holds the
/// "before" score dimmed; when the "after" score lands, it sweeps up to it and a tick keeps the starting point.
struct ScoreMeter: View {
    let before: Int?
    let after: Int?
    var isRunning = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func fraction(_ v: Int?) -> CGFloat { CGFloat(min(max(v ?? 0, 0), 100)) / 100 }

    private var delta: String? {
        guard let b = before else { return nil }
        guard let a = after else { return "from \(b)" }
        return "from \(b), \(a >= b ? "+" : "−")\(abs(a - b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .center, spacing: 8) {
                if compact { Text("Score").foregroundStyle(Theme.muted) } else { Text("Score").font(.headline) }
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
                if let d = delta { Text(d).font(.callout.monospacedDigit()).foregroundStyle(Theme.muted) }
                Text(after.map(String.init) ?? "–")
                    .font((compact ? Font.body : .title3).weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .frame(minWidth: compact ? 30 : 40)
                    .padding(.horizontal, 10).padding(.vertical, compact ? 2 : 4)
                    .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
            }
            track.frame(height: compact ? 12 : 20)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: after)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prompt score")
        .accessibilityValue(after.map { a in "\(a) out of 100" + (before.map { ", up from \($0)" } ?? "") }
                            ?? before.map { "\($0) out of 100 before improving" } ?? "Pending")
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let fill = fraction(after ?? before)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    ForEach(1..<10) { i in
                        if CGFloat(i) / 10 > fill + 0.02 {
                            Circle().fill(Theme.muted.opacity(0.4)).frame(width: 4, height: 4)
                                .position(x: w * CGFloat(i) / 10, y: h / 2)
                        }
                    }
                    LinearGradient(gradient: Theme.sunrise, startPoint: .leading, endPoint: .trailing)
                        .mask(alignment: .leading) { Rectangle().frame(width: w * fill) }
                        .opacity(after == nil ? 0.45 : 1)
                    if let b = before, after != nil {
                        Capsule().fill(Color.black.opacity(0.32)).frame(width: 2, height: h * 0.5)
                            .position(x: w * fraction(b), y: h / 2)
                    }
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                if after != nil || before != nil {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 7, height: h + 6)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .position(x: min(max(w * fill, 3.5), w - 3.5), y: h / 2)
                }
            }
        }
    }
}
