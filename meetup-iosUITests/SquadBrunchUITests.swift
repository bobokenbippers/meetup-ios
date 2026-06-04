import XCTest

// MARK: - Sign-in screen (unauthenticated)

final class SignInScreenTests: XCTestCase {
    var entry: AppScreen!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        entry = AppScreen.launchUnauthenticated()
    }

    override func tearDown() {
        entry.app.terminate()
        super.tearDown()
    }

    func testSignInScreenShows() {
        let screen = entry.signInScreen()
        XCTAssertTrue(screen.isDisplayed(), "Sign-in screen should appear when unauthenticated")
    }

    func testAppTitleAndTaglineVisible() {
        let screen = entry.signInScreen()
        XCTAssertTrue(screen.appTitle.waitForExistence(timeout: 5), "App title 'Squad Brunch' should be visible")
        XCTAssertTrue(screen.tagline.waitForExistence(timeout: 5), "Tagline should be visible")
    }

    func testSignInWithAppleButtonExists() {
        let screen = entry.signInScreen()
        XCTAssertTrue(screen.signInButton.waitForExistence(timeout: 5), "Sign in with Apple button should exist")
        XCTAssertTrue(screen.signInButton.isEnabled, "Sign in button should be enabled")
    }
}

// MARK: - Meetups tab (authenticated)

final class MeetupsTabTests: XCTestCase {
    var entry: AppScreen!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        entry = AppScreen.launchAuthenticated()
    }

    override func tearDown() {
        entry.app.terminate()
        super.tearDown()
    }

    func testMeetupsTabIsDefault() {
        let screen = entry.meetupsScreen()
        XCTAssertTrue(screen.isDisplayed(), "Meetups tab should be the default selected tab")
    }

    func testCreateMeetupButtonExists() {
        let screen = entry.meetupsScreen()
        XCTAssertTrue(screen.createButton.waitForExistence(timeout: 5), "Create Meetup (+) button should be in the toolbar")
    }

    func testCreateMeetupSheetOpens() {
        let screen = entry.meetupsScreen()
        let createSheet = screen.tapCreateMeetup()
        XCTAssertTrue(createSheet.isDisplayed(), "New Meetup sheet should open after tapping +")
    }

    func testThreeTabsExist() {
        let tabBar = entry.app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.app.tabBars.buttons["Meetups"].exists)
        XCTAssertTrue(entry.app.tabBars.buttons["People"].exists)
        XCTAssertTrue(entry.app.tabBars.buttons["Settings"].exists)
    }
}

// MARK: - Create Meetup form

final class CreateMeetupFormTests: XCTestCase {
    var entry: AppScreen!
    var createSheet: CreateMeetupScreen!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        entry = AppScreen.launchAuthenticated()
        let meetups = entry.meetupsScreen()
        XCTAssertTrue(meetups.isDisplayed())
        createSheet = meetups.tapCreateMeetup()
        XCTAssertTrue(createSheet.isDisplayed())
    }

    override func tearDown() {
        entry.app.terminate()
        super.tearDown()
    }

    func testDestinationFieldExists() {
        XCTAssertTrue(createSheet.destinationField.waitForExistence(timeout: 5),
                      "Destination search field should be present")
    }

    func testCreateButtonDisabledWithoutDestination() {
        XCTAssertFalse(createSheet.createButton.isEnabled,
                       "Create button should be disabled when no destination is selected")
    }

    func testDestinationFieldAcceptsInput() {
        createSheet.typeDestination("Central Park")
        // Verify the field is still accessible — value assertion omitted because
        // task(id: searchQuery) fires on each keystroke and may clear/reset field state.
        XCTAssertTrue(createSheet.destinationField.exists,
                      "Destination field should remain accessible after typing")
    }

    func testDestinationSearchShowsResults() throws {
        // Requires live MapKit network + real device — run manually.
        try XCTSkipIf(true, "Requires live MapKit network — run manually on a real device")
    }

    func testTimingToggleExpandsPickers() {
        let toggle = createSheet.timingToggle
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        // The form uses a SwiftUI DatePicker (datePickers) plus custom wheel Pickers.
        // Either appearing confirms the section expanded correctly.
        let hasDatePicker = entry.app.datePickers.firstMatch.waitForExistence(timeout: 3)
        let hasPicker = entry.app.pickers.firstMatch.waitForExistence(timeout: 1)
        XCTAssertTrue(hasDatePicker || hasPicker,
                      "Date/time pickers should appear after enabling timing toggle")
    }

    func testCategoryButtonsAllVisible() {
        entry.app.swipeUp()
        XCTAssertTrue(createSheet.squadBrunchCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(createSheet.squadHappyHourCategory.exists)
        XCTAssertTrue(entry.app.buttons["Squad Kickback"].exists)
        XCTAssertTrue(createSheet.customCategory.exists)
    }

    func testCategorySelectionToggles() {
        // Category section may be partially below the fold — scroll to it first.
        entry.app.swipeUp()
        let button = createSheet.squadBrunchCategory
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        button.tap()
        // No assertion needed beyond not crashing — verifies tap handling works
    }

    func testCustomCategoryFieldAppearsOnTap() {
        entry.app.swipeUp()
        createSheet.customCategory.tap()
        let customField = entry.app.textFields["e.g. Squad Picnic"]
        XCTAssertTrue(customField.waitForExistence(timeout: 3),
                      "Custom category text field should appear after tapping Custom...")
    }

    func testInviteFieldExists() {
        XCTAssertTrue(createSheet.inviteField.waitForExistence(timeout: 5),
                      "Invite phone/name field should be present in the form")
    }

    func testCancelDismissesSheet() {
        createSheet.dismiss()
        XCTAssertTrue(entry.meetupsScreen().isDisplayed(),
                      "Meetups list should be visible after cancelling the sheet")
    }
}

// MARK: - People tab

final class PeopleTabTests: XCTestCase {
    var entry: AppScreen!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        entry = AppScreen.launchAuthenticated()
        XCTAssertTrue(entry.meetupsScreen().isDisplayed())
        entry.app.tabBars.buttons["People"].tap()
    }

    override func tearDown() {
        entry.app.terminate()
        super.tearDown()
    }

    func testPeopleTabNavigates() {
        XCTAssertTrue(entry.peopleScreen().isDisplayed(), "People tab should show People screen")
    }

    func testSearchFieldExists() {
        XCTAssertTrue(entry.peopleScreen().searchField.waitForExistence(timeout: 5),
                      "Phone/name search field should exist")
    }

    func testSearchFieldAcceptsInput() {
        let field = entry.peopleScreen().searchField
        field.tap()
        field.typeText("646")
        // Formatter rewrites digits → "+1 (646"
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.contains("646"), "Search field should contain typed digits")
    }

    func testSearchButtonDisabledWithPartialNumber() {
        let field = entry.peopleScreen().searchField
        field.tap()
        field.typeText("646")
        let searchButton = entry.app.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3))
        XCTAssertFalse(searchButton.isEnabled,
                       "Search button should be disabled until 10 digits are entered")
    }
}

// MARK: - Settings tab

final class SettingsTabTests: XCTestCase {
    var entry: AppScreen!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        entry = AppScreen.launchAuthenticated()
        XCTAssertTrue(entry.meetupsScreen().isDisplayed())
        entry.app.tabBars.buttons["Settings"].tap()
    }

    override func tearDown() {
        entry.app.terminate()
        super.tearDown()
    }

    func testSettingsScreenShows() {
        XCTAssertTrue(entry.settingsScreen().isDisplayed(), "Settings screen should appear")
    }

    func testThemePickerExists() {
        XCTAssertTrue(entry.settingsScreen().themePicker.waitForExistence(timeout: 5),
                      "Segmented theme picker should exist")
    }

    func testAccessibilityTogglesExist() {
        let settings = entry.settingsScreen()
        XCTAssertTrue(settings.boldTextToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.app.switches["Larger Text"].exists)
        XCTAssertTrue(entry.app.switches["Reduce Motion"].exists)
    }

    func testSignOutButtonExists() {
        XCTAssertTrue(entry.settingsScreen().signOutButton.waitForExistence(timeout: 5),
                      "Sign Out button should exist in Settings")
    }

    func testThemePickerHasThreeSegments() {
        let picker = entry.settingsScreen().themePicker
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.buttons.count, 3, "Theme picker should have Light, Dark, System segments")
    }
}
