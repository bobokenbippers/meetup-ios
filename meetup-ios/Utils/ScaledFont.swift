import SwiftUI

/// A fixed-point font that scales with the user's Dynamic Type ("Larger Text")
/// setting, while preserving the app's hand-tuned point sizes at the default size.
///
/// Replaces `.font(.system(size:weight:design:))`, which is locked at a fixed
/// point size and ignores Dynamic Type. Backed by `@ScaledMetric` so the size
/// grows/shrinks proportionally with the accessibility text-size slider.
private struct ScaledFontModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: size,
                weight: legibilityWeight == .bold ? weight.appBoldTextAdjusted : weight,
                design: design
            )
        )
    }
}

extension Font.Weight {
    var appBoldTextAdjusted: Font.Weight {
        if self == .ultraLight || self == .thin || self == .light || self == .regular {
            return .semibold
        }
        if self == .medium || self == .semibold {
            return .bold
        }
        if self == .bold {
            return .heavy
        }
        return .black
    }
}

extension View {
    /// Dynamic-Type-aware replacement for `.font(.system(size:weight:design:))`.
    /// At the default text size the rendered size equals `size`; it scales from there.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}
