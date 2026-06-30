import Testing
@testable import meetup_ios

@Suite("AppEnvironment")
struct AppEnvironmentTests {
    @Test("reads OpenRouteService key from JSON app env")
    func readsOpenRouteServiceKeyFromJSON() {
        let environment = AppEnvironment(raw: #"{"OPENROUTESERVICE_API_KEY":"ors-key","OTHER":"value"}"#)

        #expect(environment.value(for: "OPENROUTESERVICE_API_KEY") == "ors-key")
    }

    @Test("reads OpenRouteService key from dotenv-style app env")
    func readsOpenRouteServiceKeyFromDotenv() {
        let environment = AppEnvironment(raw: """
        # local app secrets
        OPENROUTESERVICE_API_KEY = "ors-key"
        OTHER=value
        """)

        #expect(environment.value(for: "OPENROUTESERVICE_API_KEY") == "ors-key")
    }

    @Test("ignores unresolved build setting placeholders")
    func ignoresBuildSettingPlaceholders() {
        let environment = AppEnvironment(raw: "$(APP_ENV)")

        #expect(environment.value(for: "OPENROUTESERVICE_API_KEY") == nil)
    }
}
