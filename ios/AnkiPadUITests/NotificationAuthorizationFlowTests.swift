import XCTest
import UserNotifications

final class NotificationAuthorizationFlowTests: StudyFlowTestSupport {
    func testActualNotificationAuthorizationAndScheduleReplacement() throws {
        let app = makeApplication()
        app.launchArguments = ["--uitest-reminders"]
        app.launch()
        let form = app.collectionViews["reminder-form"]
        func open() {
            if !app.navigationBars["設定"].exists {
                tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
                tapTestMenuAction(titles: ["設定"], in: app)
            }
            let links = app.buttons.matching(identifier: "reminder-open")
            revealSettingsControl(links.element, in: app)
            tapTestControl(links, in: app)
            requireTestCondition("Reminder form is foreground", in: app) { form.isHittable }
        }
        func toggle(_ id: String, _ desired: Bool) {
            let controls = app.switches.matching(identifier: id)
            revealFormControl(controls.element, in: form, topInset: 40, bottomInset: 10, searchUpward: false)
            setTestSwitch(controls, enabled: desired, in: app)
        }
        func save() {
            let buttons = app.buttons.matching(identifier: "reminder-save")
            revealFormControl(buttons.element, in: form, topInset: 40, bottomInset: 10)
            tapTestControl(buttons, in: app)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可"]))
            // Optional OS prompt; if present its action must still be unique.
            if allow.element.waitForExistence(timeout: 3) {
                tapTestControl(allow, in: springboard, keyboard: .keep)
            }
            requireTestCondition("Reminder save completed without an error", in: app) {
                !app.navigationBars["学習リマインダー"].exists
            }
            XCTAssertFalse(app.alerts.element.exists, reminderFailureContext(app))
        }
        func snapshot() throws -> Set<String> {
            let statuses = app.staticTexts.matching(identifier: "reminder-native-schedule")
            revealFormControl(statuses.element, in: form, topInset: 40, bottomInset: 10)
            let status = try XCTUnwrap(waitForTestControl(statuses, in: app, purpose: .observation))
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
        XCTAssertFalse(app.alerts.element.exists)
    }
}
