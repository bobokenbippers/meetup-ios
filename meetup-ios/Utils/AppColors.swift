import SwiftUI

// Centralized app color palette — edit here, change propagates everywhere.
// Backgrounds and surfaces are adaptive (light/dark); accent and status
// colors are fixed and read well on both schemes.
extension Color {

    // MARK: - Adaptive backgrounds

    static let appBackground = Color(uiColor: .appBackground)
    static let appSurface    = Color(uiColor: .appSurface)

    // MARK: - Primary accent (indigo-violet — works on both schemes)

    static let coral = Color(red: 0.424, green: 0.341, blue: 0.773)  // #6C57C5

    // MARK: - Status semantic colors

    static let statusPending = Color(red: 0.686, green: 0.631, blue: 0.953)
    static let statusLate    = Color(red: 0.949, green: 0.349, blue: 0.349)
    static let statusLive    = Color(red: 0.180, green: 0.835, blue: 0.451)

    // MARK: - Punctuality tile colors

    static let statusEnRoute     = Color(red: 0.118, green: 0.565, blue: 1.000)
    static let statusInvited     = Color(red: 0.560, green: 0.560, blue: 0.620)
    static let statusRunningLate = Color(red: 1.000, green: 0.620, blue: 0.000)

    // MARK: - Participant avatar / map pin palette

    static let participantPalette: [Color] = [
        Color(red: 0.424, green: 0.341, blue: 0.773),
        Color(red: 0.482, green: 0.361, blue: 0.749),
        Color(red: 0.118, green: 0.565, blue: 1.000),
        Color(red: 0.180, green: 0.800, blue: 0.443),
        Color(red: 0.910, green: 0.212, blue: 0.278),
        Color(red: 0.000, green: 0.780, blue: 0.941),
    ]

    // MARK: - Category gradients

    static let categoryGradientFoodStart = Color(red: 0.388, green: 0.302, blue: 0.718)
    static let categoryGradientFoodEnd   = Color(red: 0.235, green: 0.180, blue: 0.478)
}

extension UIColor {
    // Near-black with purple tint in dark; soft lavender in light.
    static let appBackground = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1)  // #0F0F19
            : UIColor(red: 0.96, green: 0.95, blue: 1.00, alpha: 1)  // #F5F2FF
    }

    // Dark elevated surface in dark; slightly deeper lavender card in light.
    static let appSurface = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.16, alpha: 1)  // #1A1A29
            : UIColor(red: 0.90, green: 0.88, blue: 0.98, alpha: 1)  // #E6E0FA
    }
}
