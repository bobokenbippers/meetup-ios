import SwiftUI

struct LocationSharingBanner: View {
    let meetup: Meetup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .scaledFont(size: 11, weight: .semibold)
                Text("Sharing location for \(meetup.destinationName)")
                    .scaledFont(size: 12, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .scaledFont(size: 10, weight: .semibold)
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.coral)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }
}
