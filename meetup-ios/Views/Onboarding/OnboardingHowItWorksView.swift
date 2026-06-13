import SwiftUI

struct OnboardingHowItWorksView: View {
    let onNext: () -> Void

    private let steps: [(emoji: String, title: String, subtitle: String)] = [
        ("🎯", "Create a meetup", "Pick a spot, invite your crew"),
        ("📍", "Share your location", "Everyone sees who's close, who's late"),
        ("🧾", "Split the bill", "Scan receipts and settle up"),
    ]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("How it works")
                    .scaledFont(size: 36, weight: .black, design: .rounded)
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(.bottom, 48)

                VStack(spacing: 24) {
                    ForEach(steps, id: \.title) { step in
                        HStack(alignment: .top, spacing: 20) {
                            Text(step.emoji)
                                .scaledFont(size: 36)
                                .frame(width: 48)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(step.title)
                                    .scaledFont(size: 18, weight: .bold)
                                    .foregroundStyle(DS.Color.textPrimary)
                                Text(step.subtitle)
                                    .scaledFont(size: 15)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 32)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    Text("Sounds good →")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(.white) // on coral background
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    OnboardingHowItWorksView { }
}
