import SwiftUI
import Testing
@testable import meetup_ios

@Suite("MeetupCardSurface")
struct MeetupCardSurfaceTests {
    private func surface(_ category: String?, status: String = "active", participant: String = "going") -> MeetupCardSurface {
        MeetupCardSurface.classify(category: category, meetupStatus: status, participantStatus: participant)
    }

    @Test("active food/nightlife/coffee cards use a dark gradient and light text")
    func darkGradientsUseLightText() {
        for category in ["Brunch", "Dinner", "Happy Hour", "Cocktails", "Coffee", "Café"] {
            let s = surface(category)
            #expect(s.usesLightText, "\(category) should use light text on its dark gradient")
        }
    }

    @Test("active card with no themed category uses a light surface and dark text")
    func neutralActiveCardUsesDarkText() {
        // This is the regression guard for the "white title on a light card" bug:
        // an unmatched active category must NOT request light text.
        let s = surface("Tap & Grill")
        #expect(s == .activeNeutral)
        #expect(!s.usesLightText)
    }

    @Test("inactive or invited cards never request light text")
    func restingCardsUseDarkText() {
        #expect(surface("Brunch", status: "ended").usesLightText == false)
        #expect(surface("Brunch", participant: "invited").usesLightText == false)
    }

    @Test("background style and text color come from the same classification")
    func backgroundAndTextStayConsistent() {
        // Whatever the public helpers return must agree with the single source.
        for category in [nil, "Brunch", "Coffee", "Tap & Grill", "Kickback"] {
            let s = MeetupCardSurface.classify(category: category, meetupStatus: "active", participantStatus: "going")
            #expect(meetupHasDarkBackground(category: category, meetupStatus: "active", participantStatus: "going") == s.usesLightText)
        }
    }
}
