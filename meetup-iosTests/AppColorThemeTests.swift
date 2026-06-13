import Foundation
import Testing
@testable import meetup_ios

@Suite("AppColorTheme")
struct AppColorThemeTests {
    @Test("themes expose stable labels")
    func labels() {
        #expect(AppColorTheme.standard.label == "Standard")
        #expect(AppColorTheme.knicks.label == "Knicks")
    }

    @Test("unknown persisted value falls back to standard")
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
    }
}
