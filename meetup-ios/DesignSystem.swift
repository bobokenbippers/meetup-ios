import SwiftUI

// MARK: - Typography
enum Typography {
    enum Font {
        static let display = SwiftUI.Font.system(size: 30, weight: .black)
        static let title = SwiftUI.Font.system(size: 20, weight: .bold)
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15, weight: .regular)
        static let label = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 12, weight: .regular) // hard floor
    }
}

// MARK: - Spacing
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Semantic Colors
extension Color {
    // Surfaces
    static let surface = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "0E0E12"))
    static let surfaceCard = Color(light: Color(hex: "F5F4F8"), dark: Color(hex: "1A1A20"))
    static let surfaceElevated = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "24242C"))
    static let surfaceInput = Color(light: Color(hex: "EFEEF3"), dark: Color(hex: "1E1E26"))
    // Text
    static let textPrimary = Color(light: Color(hex: "14131A"), dark: Color(hex: "F5F4F8"))
    static let textSecondary = Color(light: Color(hex: "6B6975"), dark: Color(hex: "A6A4B0"))
    // Border
    static let borderSubtle = Color(light: Color(hex: "E4E2EA"), dark: Color(hex: "2C2B34"))
    // Brand (was "coral" — now brand)
    static let brand = Color(light: Color(hex: "6C57C5"), dark: Color(hex: "8A78E0"))

    // Light/dark adaptive initializer
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        }))
    }

    // Hex initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - DS namespace (canonical token surface)
/// Canonical design-token surface. Views should prefer `DS.Color.*`,
/// `DS.Font.*`, and `DS.Spacing.*` over raw literals so swaps propagate
/// from one place.
enum DS {
    enum Color {
        static let background    = SwiftUI.Color.appBackground
        static let surface       = SwiftUI.Color.appSurface
        static let textPrimary   = SwiftUI.Color.textPrimary
        static let textSecondary = SwiftUI.Color.textSecondary
        /// Indigo brand accent — #6C57C5 light, #8A78E0 dark.
        static let accent        = SwiftUI.Color.brand
    }

    enum Font {
        /// Large hero headline — scales with Dynamic Type (largeTitle + black weight).
        static let hero     = SwiftUI.Font.largeTitle.weight(.black)
        static let title    = Typography.Font.title
        static let headline = Typography.Font.headline
        static let body     = Typography.Font.body
        static let caption  = Typography.Font.caption
    }

    enum Spacing {
        static let xs: CGFloat =  4
        static let sm: CGFloat =  8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 48
    }
}

// MARK: - Card style
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Glass card
/// `.ultraThinMaterial` frosted-glass surface with 18 pt corners and a subtle shadow.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}

// MARK: - DS primary button
/// Pill-shaped primary button using the brand indigo accent (#6C57C5).
struct DSButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(DS.Color.accent)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.18, bounce: 0.25), value: configuration.isPressed)
    }
}

extension View {
    /// Applies the DS primary pill-button appearance to any view acting as a button label.
    func dsButtonStyle() -> some View {
        self.buttonStyle(DSButtonStyle())
    }
}
