import XCTest

// MARK: - App launcher

struct AppScreen {
    let app: XCUIApplication

    static func launchUnauthenticated() -> AppScreen {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        return AppScreen(app: app)
    }

    static func launchAuthenticated() -> AppScreen {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return AppScreen(app: app)
    }

    func signInScreen() -> SignInScreen { SignInScreen(app: app) }
    func meetupsScreen() -> MeetupsScreen { MeetupsScreen(app: app) }
    func peopleScreen() -> PeopleScreen { PeopleScreen(app: app) }
    func settingsScreen() -> SettingsScreen { SettingsScreen(app: app) }
}

// MARK: - Sign In screen

struct SignInScreen {
    let app: XCUIApplication

    var appTitle: XCUIElement { app.staticTexts["Squad Brunch"] }
    var tagline: XCUIElement { app.staticTexts["Know who's on their way."] }
    var signInButton: XCUIElement { app.buttons["Sign in with Apple"] }

    func isDisplayed() -> Bool {
        appTitle.waitForExistence(timeout: 5)
    }
}

// MARK: - Meetups list screen (Meetups tab)

struct MeetupsScreen {
    let app: XCUIApplication

    var createButton: XCUIElement { app.buttons["btn_create_meetup"] }
    var navTitle: XCUIElement { app.navigationBars["Meetups"] }

    func isDisplayed() -> Bool {
        navTitle.waitForExistence(timeout: 5)
    }

    @discardableResult
    func tapCreateMeetup() -> CreateMeetupScreen {
        createButton.tap()
        return CreateMeetupScreen(app: app)
    }
}

// MARK: - Create Meetup sheet

struct CreateMeetupScreen {
    let app: XCUIApplication

    var navTitle: XCUIElement { app.navigationBars["New Meetup"] }
    var destinationField: XCUIElement { app.textFields["field_destination"] }
    var createButton: XCUIElement { app.buttons["btn_create_confirm"] }
    var cancelButton: XCUIElement { app.buttons["Cancel"] }
    var timingToggle: XCUIElement { app.switches["Set a target arrival time"] }
    var squadBrunchCategory: XCUIElement { app.buttons["Squad Brunch"] }
    var squadHappyHourCategory: XCUIElement { app.buttons["Squad Happy Hour"] }
    var customCategory: XCUIElement { app.buttons["Custom..."] }
    var inviteField: XCUIElement { app.textFields["Name or +1 (646) 946-6861"] }

    func isDisplayed() -> Bool {
        navTitle.waitForExistence(timeout: 5)
    }

    func typeDestination(_ text: String) {
        destinationField.tap()
        destinationField.typeText(text)
    }

    func dismiss() {
        cancelButton.tap()
    }
}

// MARK: - People screen

struct PeopleScreen {
    let app: XCUIApplication

    var navTitle: XCUIElement { app.navigationBars["People"] }
    var searchField: XCUIElement { app.textFields["Name or +1 (646) 946-6861"] }

    func isDisplayed() -> Bool {
        navTitle.waitForExistence(timeout: 5)
    }

    func navigate(from app: XCUIApplication) -> PeopleScreen {
        app.tabBars.buttons["People"].tap()
        return self
    }
}

// MARK: - Settings screen

struct SettingsScreen {
    let app: XCUIApplication

    var navTitle: XCUIElement { app.navigationBars["Settings"] }
    var themePicker: XCUIElement { app.segmentedControls.firstMatch }
    var signOutButton: XCUIElement { app.buttons["Sign Out"] }
    var boldTextToggle: XCUIElement { app.switches["Bold Text"] }

    func isDisplayed() -> Bool {
        navTitle.waitForExistence(timeout: 5)
    }

    func navigate(from app: XCUIApplication) -> SettingsScreen {
        app.tabBars.buttons["Settings"].tap()
        return self
    }
}
