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
