import SwiftUI

// Centralized app color palette — edit here, change propagates everywhere.
extension Color {
    // Primary accent: soft indigo replacing the old coral/orange (#FF6B47)
    static let coral = Color(red: 0.424, green: 0.341, blue: 0.773)  // #6C57C5 deep indigo-violet

    // Status semantic colors
    static let statusPending = Color(red: 0.686, green: 0.631, blue: 0.953)  // lavender (was yellow)
    static let statusLate    = Color(red: 0.949, green: 0.349, blue: 0.349)  // muted red
    static let statusLive    = Color(red: 0.180, green: 0.835, blue: 0.451)  // green

    // Ordered palette for participant avatars and map pins (indigo-first, was orange-first)
    static let participantPalette: [Color] = [
        Color(red: 0.424, green: 0.341, blue: 0.773),  // indigo
        Color(red: 0.482, green: 0.361, blue: 0.749),  // violet
        Color(red: 0.118, green: 0.565, blue: 1.000),  // blue
        Color(red: 0.180, green: 0.800, blue: 0.443),  // green
        Color(red: 0.910, green: 0.212, blue: 0.278),  // red
        Color(red: 0.000, green: 0.780, blue: 0.941),  // cyan
    ]

    // Category card gradient: food/brunch (was warm orange-red, now deep indigo)
    static let categoryGradientFoodStart = Color(red: 0.388, green: 0.302, blue: 0.718)
    static let categoryGradientFoodEnd   = Color(red: 0.235, green: 0.180, blue: 0.478)
}
