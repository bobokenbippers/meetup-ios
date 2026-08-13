import Foundation
import Testing
@testable import meetup_ios

@Suite("AppColorTheme")
struct AppColorThemeTests {
    @Test("themes expose stable labels")
    func labels() {
        #expect(AppColorTheme.standard.label == "Standard")
        #expect(AppColorTheme.aperitif.label == "Aperitif")
        #expect(AppColorTheme.coastal.label == "Coastal")
        #expect(AppColorTheme.allCases == [.standard, .aperitif, .coastal])
    }

    @Test("removed or unknown persisted value falls back to standard")
    func currentFallsBackToStandard() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "appColorTheme")
        defer {
            if let previous {
                defaults.set(previous, forKey: "appColorTheme")
            } else {
                defaults.removeObject(forKey: "appColorTheme")
            }
        }

        defaults.set("heat", forKey: "appColorTheme")
        #expect(AppColorTheme.current == .standard)

        defaults.set("knicks", forKey: "appColorTheme")
        #expect(AppColorTheme.current == .standard)
    }
}
