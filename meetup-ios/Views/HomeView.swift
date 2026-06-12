import SwiftUI

struct HomeView: View {
    @Environment(NavigationState.self) private var navState
    private var locationManager: LocationManager { LocationManager.shared }

    var body: some View {
        @Bindable var nav = navState
        TabView(selection: $nav.selectedTab) {
            MeetupsListView()
                .tabItem { Label("Meetups", systemImage: "person.2.circle") }
                .tag(NavigationState.Tab.meetups)
            PeopleListView()
                .tabItem { Label("People", systemImage: "person.crop.circle") }
                .tag(NavigationState.Tab.people)
            DirectMessagesView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                .tag(NavigationState.Tab.messages)
            GamesHomeView()
                .tabItem { Label("Games", systemImage: "gamecontroller.fill") }
                .tag(NavigationState.Tab.games)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(NavigationState.Tab.settings)
        }
        .tint(Color.coral)
        .safeAreaInset(edge: .top, spacing: 0) {
            if locationManager.isTracking, let meetup = locationManager.trackingMeetup {
                LocationSharingBanner(meetup: meetup) {
                    nav.selectedTab = .meetups
                    nav.pendingMeetupId = meetup.id
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: locationManager.isTracking)
    }
}
