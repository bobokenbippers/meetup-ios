import SwiftUI
import Testing
@testable import meetup_ios

@Suite("ScaledFont")
struct ScaledFontTests {
    @Test("bold text preference promotes app font weights")
    func boldTextPromotesWeights() {
        #expect(Font.Weight.regular.appBoldTextAdjusted == .semibold)
        #expect(Font.Weight.medium.appBoldTextAdjusted == .bold)
        #expect(Font.Weight.semibold.appBoldTextAdjusted == .bold)
        #expect(Font.Weight.bold.appBoldTextAdjusted == .heavy)
        #expect(Font.Weight.heavy.appBoldTextAdjusted == .black)
    }
}
