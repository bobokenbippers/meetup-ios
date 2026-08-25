import SwiftUI

struct LocationSharingBanner: View {
    let meetup: Meetup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: "location.fill")
                        .scaledFont(size: 12, weight: .bold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("LIVE SHARING")
                        .scaledFont(size: 10, weight: .black)
                        .foregroundStyle(Color.appAccentForeground.opacity(0.72))
                    Text(meetup.destinationName)
                        .scaledFont(size: 14, weight: .bold)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.circle.fill")
                    .scaledFont(size: 18, weight: .semibold)
                    .opacity(0.92)
            }
            .foregroundStyle(Color.appAccentForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color.coral,
                        Color(red: 0.980, green: 0.486, blue: 0.380)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.coral.opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live location sharing")
        .accessibilityValue(meetup.destinationName)
        .accessibilityHint("Opens the active meetup so you can review or stop sharing.")
    }
}
