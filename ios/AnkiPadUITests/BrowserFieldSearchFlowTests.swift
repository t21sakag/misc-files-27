import XCTest

final class BrowserFieldSearchFlowTests: BrowserSearchTestSupport {
    func testNamedFieldTextSearchCancelExactAndLiteralStar() throws {
        let (app, back) = try fixture()
        openFields(back: back, mode: "文字列を含む", text: "cat", in: app)
        tapTestControl(app.buttons.matching(identifier: "field-search-cancel"), in: app)
        expectRows([0, 1, 2, 3, 4], in: app)
        XCTAssertEqual(app.staticTexts["browser-results"].value as? String, "")
        openFields(back: back, mode: "文字列を含む", text: "cat", in: app)
        apply(app); expectRows([0, 1], in: app)
        openFields(back: back, mode: "完全一致", text: "cat", in: app)
        apply(app); expectRows([0], in: app)
        openFields(back: back, mode: "文字列を含む", text: "*", in: app)
        apply(app); expectRows([2], in: app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        app.terminate(); app.launchArguments = []; app.launch()
        openBrowser("", in: app); expectRows([0, 1, 2, 3, 4], in: app)
    }
    func testNamedFieldEmptyNonemptyExistsAndCurrentQueryIntersection() throws {
        let (app, back) = try fixture()
        openFields(back: back, mode: "空のフィールド", in: app)
        apply(app); expectRows([3], in: app)
        openFields(back: back, mode: "空でないフィールド", in: app)
        apply(app); expectRows([0, 1, 2, 4], in: app)
        openFields(back: back, mode: "フィールドの存在", in: app)
        apply(app); expectRows([0, 1, 2, 3, 4], in: app)
        tapTestControl(app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "閉じる")), in: app)
        openBrowser("row0", in: app); expectRows([0], in: app)
        openFields(back: back, mode: "文字列を含む", text: "cat", combine: true, in: app)
        apply(app); expectRows([0], in: app)
        openFields(back: back, mode: "完全一致", text: "concatenate", combine: true, in: app)
        apply(app); expectRows([], in: app)
    }
}
