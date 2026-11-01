#if DEBUG
import SwiftUI

/// Selecting the App entry point avoids changing the normal WindowGroup's
/// view type or adding a focus wrapper to the real app tree.
struct ToolbarFocusReproductionApp: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("appearance") private var appearance = "system"
    init() {
        do { try UITestIsolation.prepare() }
        catch { fatalError("Could not initialize isolated UI test storage: \(error)") }
    }
    var body: some Scene {
        WindowGroup {
            StudyThemeContainer { ToolbarFocusReproductionView() }
                .environment(\.locale, AppText.locale)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

/// Diagnostic scene only: same real child and presentation boundaries, with
/// no collection/network/model. Success here does not fix the main app crash.
struct ToolbarFocusReproductionView: View {
    @State private var showingSettings = false
    @State private var configuration = ReviewToolbarConfiguration()

    var body: some View {
        NavigationStack {
            List {
                Button(AppText.localized("設定")) { showingSettings = true }
                    .accessibilityIdentifier("focus-repro-settings")
            }
            .studyThemeSurface().navigationTitle("Checks")
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form {
                    NavigationLink(AppText.localized("操作バーの設定")) {
                        ReviewToolbarSettingsView(configuration: $configuration)
                    }.accessibilityIdentifier("focus-repro-toolbar")
                }
                .accessibilityIdentifier("focus-repro-form")
                .studyThemeSurface().navigationTitle(AppText.localized("設定"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppText.localized("キャンセル")) { showingSettings = false }
                            .accessibilityIdentifier("focus-repro-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppText.localized("保存")) { showingSettings = false }
                            .accessibilityIdentifier("focus-repro-save")
                    }
                }
            }
        }
    }
}
#endif
