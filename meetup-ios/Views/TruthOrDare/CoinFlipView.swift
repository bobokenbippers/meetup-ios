import SwiftUI
import UIKit

/// Full-screen coin flip stage. The coin's outcome comes from the
/// server (`result`); this view only animates toward it, so every
/// player lands on the same face. The current player taps to flip;
/// everyone else watches the same animation when the result syncs in.
struct CoinFlipView: View {
    let isMyTurn: Bool
    let playerName: String
    /// "heads" | "tails" once the server has decided; nil before the flip.
    let result: String?
    /// True while the flip RPC is in flight.
    let isFlipping: Bool
    let onFlip: () -> Void
    /// Called once the coin has settled, after the suspense beat.
    let onLanded: () -> Void

    @State private var angle: Double = 0
    @State private var showingBack = false
    @State private var isAnimating = false
    @State private var hasLanded = false
    @State private var idlePulse = false

    private var landedFace: CoinFace {
        result == "tails" ? .dare : .truth
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                Text(isMyTurn ? "Your turn" : "\(playerName)'s turn")
                    .scaledFont(size: 26, weight: .black)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(statusLine)
                    .scaledFont(size: 14)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            coin
                .frame(width: 220, height: 220)
                .scaleEffect(idlePulse && canTap ? 1.04 : 1.0)
                .animation(
                    canTap
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: idlePulse
                )
                .onTapGesture {
                    guard canTap else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onFlip()
                }
                .accessibilityLabel(canTap ? "Tap to flip the coin" : "Coin")
                .accessibilityIdentifier("coin_flip")

            VStack(spacing: 4) {
                Text("Heads = Truth   ·   Tails = Dare")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("The coin decides. No takebacks.")
                    .scaledFont(size: 11)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            idlePulse = true
            if result != nil { runFlipAnimation() }
        }
        .onChange(of: result) { _, newValue in
            if newValue != nil { runFlipAnimation() }
        }
    }

    private var canTap: Bool {
        isMyTurn && result == nil && !isFlipping && !isAnimating
    }

    private var statusLine: String {
        if isAnimating { return "No takebacks…" }
        if isFlipping { return "Flipping…" }
        if isMyTurn { return "Tap the coin to flip" }
        return "Waiting for \(playerName) to flip the coin"
    }

    // MARK: - Coin

    private var coin: some View {
        ZStack {
            // Glow behind the coin
            Circle()
                .fill(faceShown.glowColor.opacity(0.35))
                .blur(radius: 36)
                .scaleEffect(1.1)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: faceShown.bodyColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(.white.opacity(0.25), lineWidth: 5)
                    .padding(6)

                faceContent
                    // The back of an x-axis flip renders mirrored; un-mirror
                    // the content so the labels stay readable mid-spin.
                    .scaleEffect(y: showingBack ? -1 : 1)
            }
            .modifier(CoinFlipEffect(showingBack: $showingBack, angle: angle))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        }
    }

    /// Which face design is visible at the current spin angle. The
    /// "front" (even half-turns) is the landed face once a result
    /// exists; the back alternates in during the spin for flicker.
    private var faceShown: CoinFace {
        guard result != nil else { return .unknown }
        return showingBack ? landedFace.opposite : landedFace
    }

    private var faceContent: some View {
        VStack(spacing: 8) {
            Image(systemName: faceShown.symbol)
                .scaledFont(size: 56, weight: .bold)
                .foregroundStyle(.white)
            Text(faceShown.label)
                .scaledFont(size: 18, weight: .black)
                .foregroundStyle(.white.opacity(0.95))
                .tracking(4)
        }
    }

    // MARK: - Animation

    private func runFlipAnimation() {
        guard !isAnimating, !hasLanded else { return }
        isAnimating = true

        // Six full spins; an even number of half-turns lands on the
        // front face, which is the server's result. The timing curve
        // launches fast and decelerates into a slow-motion settle.
        let target = angle + 6 * 360
        withAnimation(.timingCurve(0.1, 0.85, 0.3, 1.0, duration: 3.1)) {
            angle = target
        } completion: {
            land()
        }
    }

    private func land() {
        hasLanded = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // A short suspense beat on the landed face before the prompt
        // card takes over.
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            UINotificationFeedbackGenerator().notificationOccurred(landedFace == .dare ? .warning : .success)
            onLanded()
        }
    }
}

// MARK: - Face designs

private enum CoinFace {
    case truth, dare, unknown

    var opposite: CoinFace {
        switch self {
        case .truth:   return .dare
        case .dare:    return .truth
        case .unknown: return .unknown
        }
    }

    var label: String {
        switch self {
        case .truth:   return "TRUTH"
        case .dare:    return "DARE"
        case .unknown: return "FLIP"
        }
    }

    var symbol: String {
        switch self {
        case .truth:   return "quote.bubble.fill"
        case .dare:    return "flame.fill"
        case .unknown: return "questionmark"
        }
    }

    var bodyColors: [Color] {
        switch self {
        case .truth:
            return [Color(red: 0.45, green: 0.36, blue: 0.85), Color(red: 0.25, green: 0.18, blue: 0.55)]
        case .dare:
            return [Color(red: 0.95, green: 0.45, blue: 0.25), Color(red: 0.70, green: 0.18, blue: 0.15)]
        case .unknown:
            return [Color(red: 0.85, green: 0.70, blue: 0.30), Color(red: 0.60, green: 0.45, blue: 0.12)]
        }
    }

    var glowColor: Color {
        switch self {
        case .truth:   return Color.coral
        case .dare:    return Color(red: 0.95, green: 0.45, blue: 0.25)
        case .unknown: return Color(red: 0.85, green: 0.70, blue: 0.30)
        }
    }
}

/// 3D coin rotation around the x-axis. Tracks which side faces the
/// viewer via `showingBack` so the face artwork can swap mid-spin.
private struct CoinFlipEffect: GeometryEffect {
    @Binding var showingBack: Bool
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let normalized = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let back = normalized > 90 && normalized < 270
        if back != showingBack {
            DispatchQueue.main.async { showingBack = back }
        }

        var transform = CATransform3DIdentity
        transform.m34 = -1 / max(size.width, size.height)
        transform = CATransform3DRotate(transform, CGFloat(Angle(degrees: angle).radians), 1, 0, 0)
        transform = CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0)
        let recenter = ProjectionTransform(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
        return ProjectionTransform(transform).concatenating(recenter)
    }
}
