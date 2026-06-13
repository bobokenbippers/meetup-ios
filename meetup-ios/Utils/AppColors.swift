import SwiftUI

// Centralized app color palette — edit here, change propagates everywhere.
// Backgrounds and surfaces are adaptive (light/dark); accent and status
// colors are fixed and read well on both schemes.
extension Color {

    // MARK: - Adaptive backgrounds

    static let appBackground = Color(uiColor: .appBackground)
    static let appSurface    = Color(uiColor: .appSurface)

    // MARK: - Primary accent

    static var coral: Color { AppColorTheme.current.accentColor }
    static var appAccentForeground: Color { AppColorTheme.current.accentForegroundColor }
    static var appSecondaryAccent: Color { AppColorTheme.current.secondaryAccentColor }
    static var appSecondaryAccentForeground: Color { AppColorTheme.current.secondaryAccentForegroundColor }

    // MARK: - Status semantic colors

    static let statusPending = Color(red: 0.686, green: 0.631, blue: 0.953)
    static let statusLate    = Color(red: 0.949, green: 0.349, blue: 0.349)
    static let statusLive    = Color(red: 0.180, green: 0.835, blue: 0.451)

    // MARK: - Punctuality tile colors

    static let statusEnRoute     = Color(red: 0.118, green: 0.565, blue: 1.000)
    static let statusGoing       = Color(red: 0.000, green: 0.643, blue: 0.522)
    static let statusInvited     = Color(red: 0.560, green: 0.560, blue: 0.620)
    static let statusRunningLate = Color(red: 1.000, green: 0.620, blue: 0.000)

    // MARK: - Participant avatar / map pin palette

    static var participantPalette: [Color] { AppColorTheme.current.participantPalette }

    // MARK: - Category gradients

    static var categoryGradientFoodStart: Color { AppColorTheme.current.categoryGradientFoodStart }
    static var categoryGradientFoodEnd: Color { AppColorTheme.current.categoryGradientFoodEnd }
}

extension UIColor {
    // Apple-standard backgrounds: pure black/white primaries, system secondary fills.
    static let appBackground = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1)  // #000000
            : UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1)  // #FFFFFF
    }

    // Elevated surface: Apple's grouped secondary fill (#1C1C1E dark / #F5F5F7 light).
    static let appSurface = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)  // #1C1C1E
            : UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)  // #F5F5F7
    }
}
