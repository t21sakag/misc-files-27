import XCTest

final class IncomingDocumentImportFlowTests: StudyFlowTestSupport {
    private func temporaryFile(_ name: String, data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
    private func fixture(_ ext: String) throws -> URL {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "received", withExtension: ext, subdirectory: "ReceivedFixtures"))
        return try temporaryFile("received." + ext, data: Data(contentsOf: source))
    }
    private func applicationWithSentinel(_ text: String) -> XCUIApplication {
        let app = makeApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["add-note"].waitForExistence(timeout: 30))
        addUnsyncedNote(app, frontText: text)
        return app
    }
    func testReceivedAPKGImportsAfterOriginalIsRemovedAndPreservesExistingNotes() throws {
        let file = try fixture("apkg")
        let app = applicationWithSentinel("APKG existing sentinel")
        app.open(file)
        let confirm = app.buttons["incoming-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), app.debugDescription)
        // The confirmation sheet must already own a copy. The importer must
        // also retain that lease after the sheet and original both disappear.
        try FileManager.default.removeItem(at: file)
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 20))
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "Received APKG question", exists: true)
        assertBrowserContains(app, text: "APKG existing sentinel", exists: true)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        assertBrowserContains(app, text: "Received APKG question", exists: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testReceivedCOLPKGReplacesOnlyAfterConfirmationAndBackupRestoresPreviousNotes() throws {
        let file = try fixture("colpkg")
        let app = applicationWithSentinel("COLPKG previous sentinel")
        app.open(file)
        let replace = app.buttons["incoming-import-replace"]
        XCTAssertTrue(replace.waitForExistence(timeout: 30), app.debugDescription)
        replace.tap()
        let confirm = app.buttons.matching(identifier: "incoming-import-replace-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        try FileManager.default.removeItem(at: file)
        confirm.tap()
        XCTAssertTrue(replace.waitForNonExistence(timeout: 20))
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "Received COLPKG question", exists: true)
        assertBrowserContains(app, text: "COLPKG previous sentinel", exists: false)
        openMaintenance(app)
        let backup = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "backup-restore-")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 20), app.debugDescription)
        backup.tap()
        let restore = app.buttons["backup-confirm-restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10)); restore.tap()
        XCTAssertTrue(app.staticTexts["バックアップを復元しました"].waitForExistence(timeout: 40), app.debugDescription)
        app.buttons["maintenance-close"].tap()
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "COLPKG previous sentinel", exists: true)
        assertBrowserContains(app, text: "Received COLPKG question", exists: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testReceivedTSVSurvivesSourceRemovalAndImportsThroughBundledWebInterface() throws {
        let file = try temporaryFile("received.tsv", data: Data("#separator:Tab\n#html:false\nReceived TSV question\tReceived TSV answer\n".utf8))
        let app = applicationWithSentinel("TSV existing sentinel")
        app.open(file)
        let confirm = app.buttons["incoming-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), app.debugDescription)
        try FileManager.default.removeItem(at: file)
        confirm.tap()
        let load = app.webViews.buttons["読み込む"]
        XCTAssertTrue(load.waitForExistence(timeout: 45), app.debugDescription)
        tapScreenFrame(load, in: app)
        XCTAssertTrue(app.buttons["backend-close"].waitForNonExistence(timeout: 40), app.debugDescription)
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "Received TSV question", exists: true)
        assertBrowserContains(app, text: "TSV existing sentinel", exists: true)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["collection-menu"].waitForExistence(timeout: 30))
        assertBrowserContains(app, text: "Received TSV question", exists: true)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testInvalidReceivedPackageReportsFailureAndKeepsPreviousCollection() throws {
        let bytes = Data("Synthetic invalid package".utf8)
        let file = try temporaryFile("broken.apkg", data: bytes)
        let app = applicationWithSentinel("Invalid import previous sentinel")
        app.open(file)
        let confirm = app.buttons["incoming-import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), app.debugDescription)
        confirm.tap()
        let failure = app.alerts["処理できませんでした"]
        XCTAssertTrue(failure.waitForExistence(timeout: 30), app.debugDescription)
        failure.buttons["閉じる"].tap()
        waitForSyncIdle(app)
        assertBrowserContains(app, text: "Invalid import previous sentinel", exists: true)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
