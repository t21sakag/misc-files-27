import XCTest

final class TagFlowTests: StudyFlowTestSupport {
    func testHierarchicalTagsCollapseRenameMoveAndRemoveWithoutDeletingNote() {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        app.buttons["add-note"].tap()
        let front = app.textViews["note-field-0"]
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        front.tap(); front.typeText("Tag hierarchy verification")
        let tags = app.textFields["note-tags"]
        for _ in 0..<12 { if tags.exists && tags.isHittable { break }; app.collectionViews["note-form"].swipeUp() }
        waitUntilHittable(tags)
        tags.tap(); tags.typeText("TreeRoot::Branch::Leaf Unrelated")
        app.buttons["note-save"].tap()
        XCTAssertTrue(app.staticTexts["note-added"].waitForExistence(timeout: 30))
        app.buttons["note-close"].tap()
        func openTags() {
            app.buttons["collection-menu"].tap(); app.buttons["browser-open"].tap()
            let filter = app.buttons["browser-filter-menu"]
            XCTAssertTrue(filter.waitForExistence(timeout: 20))
            filter.tap(); app.buttons["タグ"].tap(); app.buttons["タグ管理"].tap()
            XCTAssertTrue(app.navigationBars["タグ管理"].waitForExistence(timeout: 20))
        }
        func setCollapsed(_ name: String, _ collapsed: Bool) {
            let button = app.buttons["tag-collapse-" + name]
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            if button.value as? String != (collapsed ? "折りたたみ" : "展開") { button.tap() }
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", collapsed ? "折りたたみ" : "展開"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 20), .completed)
        }
        func edit(_ name: String, moving: Bool, value: String) {
            app.buttons["tag-actions-" + name].tap()
            app.buttons[moving ? "別の親タグへ移動" : "名前を変更"].tap()
            let field = app.textFields["tag-edit-name"]
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            let old = field.value as? String ?? ""
            field.tap()
            if !moving { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
            field.typeText(value)
            app.buttons["tag-edit-apply"].tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 30), app.debugDescription)
        }
        openTags()
        setCollapsed("TreeRoot", false)
        setCollapsed("TreeRoot::Branch", false)
        let leaf = app.staticTexts["tag-name-TreeRoot::Branch::Leaf"]
        XCTAssertTrue(leaf.waitForExistence(timeout: 20))
        setCollapsed("TreeRoot", true)
        XCTAssertTrue(leaf.waitForNonExistence(timeout: 20))
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        openTags()
        XCTAssertEqual(app.buttons["tag-collapse-TreeRoot"].value as? String, "折りたたみ")
        XCTAssertFalse(leaf.exists)
        setCollapsed("TreeRoot", false)
        edit("TreeRoot", moving: false, value: "RenamedRoot")
        setCollapsed("RenamedRoot", false)
        XCTAssertTrue(app.staticTexts["tag-name-RenamedRoot::Branch"].waitForExistence(timeout: 20))
        edit("RenamedRoot::Branch", moving: true, value: "Target")
        setCollapsed("Target", false)
        setCollapsed("Target::Branch", false)
        XCTAssertTrue(app.staticTexts["tag-name-Target::Branch::Leaf"].waitForExistence(timeout: 20))
        app.buttons["tag-actions-Target"].tap()
        app.buttons["タグを削除"].tap()
        let confirm = app.buttons["tag-delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["tag-name-Target"].waitForNonExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["tag-name-Unrelated"].exists)
        app.navigationBars["タグ管理"].buttons["閉じる"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "検索（")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Tag hierarchy verification")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'browser-card-' AND label CONTAINS 'Tag hierarchy verification'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Tag removal must retain the note and card")
        row.tap()
        XCTAssertTrue(front.waitForExistence(timeout: 20))
        for _ in 0..<12 { if tags.exists && tags.isHittable { break }; app.collectionViews["note-form"].swipeUp() }
        XCTAssertTrue(tags.waitForExistence(timeout: 20))
        XCTAssertEqual(tags.value as? String, "Unrelated", "Rename/reparent/delete must update actual note tags without removing unrelated tags")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
