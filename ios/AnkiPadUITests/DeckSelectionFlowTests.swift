import XCTest

final class DeckSelectionFlowTests: StudyFlowTestSupport {
    func testSearchCreateChildCancelAndPersistNoteDestination() throws {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        guard tapTestControl(app.buttons.matching(identifier: "add-note"), in: app) != nil else { return }
        let formQuery = app.collectionViews.matching(identifier: "note-form")
        let form = try XCTUnwrap(waitForTestControl(formQuery, in: app, purpose: .observation))
        let front = app.textViews.matching(identifier: "note-field-0")
        let back = app.textViews.matching(identifier: "note-field-1")
        let question = "Picker destination question", answer = "Retained answer"
        guard typeInEmptyTestField(front, text: question, in: app, form: form) != nil,
              typeInEmptyTestField(back, text: answer, in: app, form: form) != nil else { return }

        let picker = app.collectionViews.matching(identifier: "deck-picker-list")
        let createForm = app.collectionViews.matching(identifier: "deck-picker-create-form")
        func openPicker() throws {
            _ = try XCTUnwrap(tapTestControl(app.buttons.matching(identifier: "note-deck-select"), in: app, form: form))
            _ = try XCTUnwrap(waitForTestControl(picker, in: app, purpose: .observation))
        }
        func enterCreationName(_ name: String) throws {
            let creating = try XCTUnwrap(waitForTestControl(createForm, in: app, purpose: .observation))
            _ = try XCTUnwrap(typeInEmptyTestField(app.textFields.matching(identifier: "deck-picker-name"),
                                                  text: name, in: app, form: creating))
        }
        func submitCreation() throws {
            _ = try XCTUnwrap(tapTestControl(app.buttons.matching(identifier: "deck-picker-create-confirm"), in: app))
        }
        func expectDestination(_ name: String) -> Bool {
            requireTestCondition("Selection returns to the editor with the expected destination", in: app) {
                let control = app.buttons.matching(identifier: "note-deck-select")
                return picker.count == 0 && createForm.count == 0 && control.count == 1 && control.element.label.contains(name)
            }
        }
        func choices(named name: String) -> XCUIElementQuery {
            picker.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                                                 "deck-picker-choice-", name))
        }
        func search(_ text: String) throws {
            let field = app.navigationBars.matching(identifier: "デッキを選択").searchFields
            _ = try XCTUnwrap(typeInEmptyTestField(field, text: text, in: app))
        }

        try openPicker()
        guard tapTestControl(app.buttons.matching(identifier: "deck-picker-add"), in: app) != nil else { return }
        try enterCreationName("Choice Parent")
        try submitCreation()
        guard expectDestination("Choice Parent") else { return }

        try openPicker()
        try search("Choice Parent")
        let parent = try XCTUnwrap(waitForTestControl(choices(named: "Choice Parent"), in: app))
        XCTContext.runActivity(named: "Open observed parent context menu at \(parent.frame)") { _ in
            parent.press(forDuration: 1)
        }
        guard tapTestMenuAction(titles: ["サブデッキを作成"], in: app) != nil else { return }
        try enterCreationName("Child")
        try submitCreation()
        let childName = "Choice Parent::Child"
        guard expectDestination(childName) else { return }

        try openPicker()
        try search("Choice Child")
        let child = try XCTUnwrap(waitForTestControl(choices(named: childName), in: app, purpose: .observation))
        let childID = String(child.identifier.dropFirst("deck-picker-choice-".count))
        XCTAssertTrue(Int64(childID).map { $0 > 0 } == true, "Destination identity must come from the rendered native choice")
        guard tapTestControl(app.buttons.matching(identifier: "deck-picker-add"), in: app) != nil else { return }
        try enterCreationName(childName)
        try submitCreation()
        guard requireTestCondition("Duplicate creation is rejected without dismissing or losing the input", in: app, condition: {
            let field = app.textFields.matching(identifier: "deck-picker-name")
            let error = app.staticTexts.matching(identifier: "deck-picker-create-error")
            return createForm.count == 1 && field.count == 1 && field.element.value as? String == childName
                && error.count == 1 && error.element.label == "同じ名前のデッキがあります。"
        }) else { return }
        guard tapTestControl(app.buttons.matching(identifier: "deck-picker-create-cancel"), in: app) != nil else { return }
        guard requireTestCondition("Creation cancel returns to the existing filtered choice", in: app, condition: {
            createForm.count == 0 && choices(named: childName).count == 1
        }) else { return }
        guard tapTestControl(app.buttons.matching(identifier: "deck-picker-cancel"), in: app) != nil else { return }
        guard expectDestination(childName) else { return }

        for (query, expected) in [(front, question), (back, answer)] {
            _ = try XCTUnwrap(waitForTestControl(query, in: app, form: form, purpose: .observation))
            guard requireTestCondition("Unsaved note content survives deck creation and cancellation", in: app, condition: {
                query.count == 1 && query.element.value as? String == expected
            }) else { return }
        }
        guard tapTestControl(app.buttons.matching(identifier: "note-save"), in: app) != nil else { return }
        guard requireTestCondition("The note is saved before closing", in: app, condition: {
            app.staticTexts.matching(identifier: "note-added").count == 1
        }) else { return }
        guard tapTestControl(app.buttons.matching(identifier: "note-close"), in: app) != nil else { return }
        _ = try XCTUnwrap(waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app))
        app.terminate()
        app.launch()
        _ = try XCTUnwrap(waitForTestControl(app.buttons.matching(identifier: "collection-menu"), in: app))
        // This is the public browser URL entry, using the ID observed in native
        // UI. No backend fixture/model injection supplies the expected destination.
        let query = "did:" + childID + " \"" + question + "\""
        var route = URLComponents(string: "studyclient://x-callback-url/browser")!
        route.queryItems = [URLQueryItem(name: "search", value: query)]
        app.open(try XCTUnwrap(route.url))
        guard requireTestCondition("Relaunch preserves the note in the exact selected child deck", in: app, condition: {
            let results = app.staticTexts.matching(identifier: "browser-results")
            return results.count == 1 && results.element.value as? String == query && results.element.label.hasPrefix("1枚")
        }) else { return }
        let results = app.collectionViews.matching(identifier: "browser-card-list")
        _ = try XCTUnwrap(waitForTestControl(results, in: app, purpose: .observation))
        let questionRow = results.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                                  "browser-front-", question))
        _ = try XCTUnwrap(waitForTestControl(questionRow, in: app, purpose: .observation))
    }
}
