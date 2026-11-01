import XCTest
import UserNotifications

class ReminderFlowTestSupport: StudyFlowTestSupport {
    struct NativeReminderSchedule {
        let pending: [[String: Any]]
        let ids: Set<String>
    }

    func openReminderSettings(in app: XCUIApplication) {
        if !app.navigationBars["設定"].exists {
            tapTestControl(app.buttons.matching(identifier: "collection-menu"), in: app)
            tapTestMenuAction(titles: ["設定"], in: app)
        }
        let links = app.buttons.matching(identifier: "reminder-open")
        revealSettingsControl(links.element, in: app)
        tapTestControl(links, in: app)
        requireTestCondition("Reminder form is foreground", in: app) {
            app.collectionViews["reminder-form"].isHittable
        }
    }

    func setReminderSwitch(_ id: String, enabled: Bool, in app: XCUIApplication, searchUpward: Bool = true) {
        let query = app.collectionViews["reminder-form"].switches.matching(identifier: id)
        // A lazy form drops offscreen AX rows. The caller knows whether its
        // next setting precedes or follows the current viewport; preserve that
        // direction instead of repeatedly dragging into the bottom boundary.
        revealFormControl(query.element, in: app.collectionViews["reminder-form"],
                          topInset: 40, bottomInset: 20, maximumAttempts: 12, searchUpward: searchUpward)
        setTestSwitch(query, enabled: enabled, in: app)
    }

    func saveReminderSettings(in app: XCUIApplication, closeSettings: Bool = false) {
        tapTestControl(app.buttons.matching(identifier: "reminder-save"), in: app,
                       form: app.collectionViews["reminder-form"])
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可"]))
        if allow.element.waitForExistence(timeout: 3) {
            tapTestControl(allow, in: system, keyboard: .keep)
        }
        requireTestCondition("Reminder save returned to settings without an error", in: app) {
            !app.navigationBars["学習リマインダー"].exists && app.navigationBars["設定"].exists
                && app.alerts.count == 0
        }
        if closeSettings {
            tapTestControl(app.buttons.matching(identifier: "settings-save"), in: app)
            waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app, purpose: .observation)
        }
    }

    func readReminderSchedule(in app: XCUIApplication) throws -> NativeReminderSchedule {
        let query = app.collectionViews["reminder-form"].staticTexts.matching(identifier: "reminder-native-schedule")
        let status = try XCTUnwrap(waitForTestControl(query, in: app, form: app.collectionViews["reminder-form"], purpose: .observation))
        let value = try XCTUnwrap(status.value as? String)
        let data = try XCTUnwrap(value.data(using: .utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pending = try XCTUnwrap(result["pending"] as? [[String: Any]])
        let ids = Set(try pending.map { try XCTUnwrap($0["id"] as? String) })
        let saved = try XCTUnwrap(result["savedIDs"] as? [String])
        XCTAssertEqual(ids.count, pending.count, value)
        XCTAssertEqual(ids, Set(saved), "Persisted IDs must equal actual OS request IDs: " + value)
        XCTAssertTrue([UNAuthorizationStatus.authorized.rawValue, UNAuthorizationStatus.provisional.rawValue,
                       UNAuthorizationStatus.ephemeral.rawValue].contains(try XCTUnwrap(result["authorizationStatus"] as? Int)), value)
        print("Actual OS reminder schedule: " + value)
        return NativeReminderSchedule(pending: pending, ids: ids)
    }

    func changeReminderMinimum(increment: Bool, expected: Int, in app: XCUIApplication) {
        let form = app.collectionViews["reminder-form"]
        let minimum = form.steppers.matching(identifier: "reminder-minimum-due")
        guard waitForTestControl(minimum, in: app, form: form, purpose: .observation) != nil else { return }
        let id = "reminder-minimum-due-" + (increment ? "Increment" : "Decrement")
        tapTestControl(minimum.buttons.matching(identifier: id), in: app)
        requireTestCondition("Reminder minimum reaches \(expected)", in: app) {
            minimum.count == 1 && minimum.element.value as? String == String(expected)
        }
    }
}
