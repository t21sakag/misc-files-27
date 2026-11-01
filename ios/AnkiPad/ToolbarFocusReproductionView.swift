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
/// no collection/network/model. Keep the three-cycle native binding/back regression independent of the main root.
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

/// Second comparison: retain actual parent, data owner and its native sheet
/// binding; keep the outer scene small to isolate omitted main-root consumers.
struct ToolbarParentFocusReproductionApp: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("appearance") private var appearance = "system"
    init() {
        do { try UITestIsolation.prepare() }
        catch { fatalError("Could not initialize isolated UI test storage: \(error)") }
    }
    var body: some Scene {
        WindowGroup {
            StudyThemeContainer { ToolbarParentFocusReproductionView() }
                .environment(\.locale, AppText.locale)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct ToolbarParentFocusReproductionView: View {
    @StateObject private var model = StudyModel()
    var body: some View {
        NavigationStack {
            List {
                Button(AppText.localized("設定")) { model.showingSettings = true }
                    .disabled(!model.profilesReady || model.busy || model.error != nil)
                    .accessibilityIdentifier("focus-parent-settings")
                if let error = model.error {
                    Text(error).accessibilityIdentifier("focus-parent-error")
                }
            }
            .studyThemeSurface().navigationTitle("Parent checks")
        }
        .sheet(isPresented: $model.showingSettings) { SettingsView(model: model) }
        .task { model.bootstrap() }
    }
}

#endif
