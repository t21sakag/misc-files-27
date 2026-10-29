import XCTest
import UserNotifications

final class NotificationAuthorizationFlowTests: StudyFlowTestSupport {
    func testActualNotificationAuthorizationAndScheduleReplacement() throws {
        let app = makeApplication()
        app.launchArguments = ["--uitest-reminders"]
        app.launch()
        func open() {
            if !app.navigationBars["設定"].exists {
                XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
                app.buttons["collection-menu"].tap(); app.buttons["設定"].tap()
            }
            let link = app.buttons["reminder-open"]
            revealSettingsControl(link, in: app); link.tap()
            XCTAssertTrue(app.collectionViews["reminder-form"].waitForExistence(timeout: 20))
        }
        func toggle(_ id: String, _ desired: Bool) {
            let outer = app.switches[id]
            revealFormControl(outer, in: app.collectionViews["reminder-form"], topInset: 40, bottomInset: 10, searchUpward: false)
            let control = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
            if (control.value as? String == "1") != desired { control.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap() }
            XCTAssertEqual(control.value as? String, desired ? "1" : "0", app.debugDescription)
        }
        func save() {
            let button = app.buttons["reminder-save"]
            revealFormControl(button, in: app.collectionViews["reminder-form"], topInset: 40, bottomInset: 10)
            button.tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可"])).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            XCTAssertTrue(app.navigationBars["学習リマインダー"].waitForNonExistence(timeout: 30), app.debugDescription)
        }
        func snapshot() throws -> Set<String> {
            let status = app.staticTexts["reminder-native-schedule"]
            revealFormControl(status, in: app.collectionViews["reminder-form"], topInset: 40, bottomInset: 10)
            let value = try XCTUnwrap(status.value as? String)
            print("Actual OS authorization and pending requests: " + value)
            let data = try XCTUnwrap(value.data(using: .utf8))
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertTrue([UNAuthorizationStatus.authorized.rawValue, UNAuthorizationStatus.provisional.rawValue, UNAuthorizationStatus.ephemeral.rawValue].contains(try XCTUnwrap(result["authorizationStatus"] as? Int)), value)
            let pending = try XCTUnwrap(result["pending"] as? [[String: Any]])
            let ids = Set(pending.compactMap { $0["id"] as? String })
            XCTAssertEqual(ids, Set(try XCTUnwrap(result["savedIDs"] as? [String])), value)
            return ids
        }
        open(); toggle("reminder-enabled", true); save()
        open(); let initial = try snapshot(); XCTAssertEqual(initial.count, 7)
        toggle("reminder-sound", false); save()
        open(); let replaced = try snapshot(); XCTAssertEqual(replaced.count, 7)
        XCTAssertTrue(replaced.isDisjoint(with: initial))
        toggle("reminder-enabled", false); save()
        open(); XCTAssertTrue(try snapshot().isEmpty)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
