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

/// Third comparison: add only inert rows to the small parent so its native
/// collection must scroll/reuse cells before opening the unchanged child.
struct ToolbarScrollFocusReproductionApp: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("appearance") private var appearance = "system"
    init() {
        do { try UITestIsolation.prepare() }
        catch { fatalError("Could not initialize isolated UI test storage: \(error)") }
    }
    var body: some Scene {
        WindowGroup {
            StudyThemeContainer { ToolbarScrollFocusReproductionView() }
                .environment(\.locale, AppText.locale)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct ToolbarScrollFocusReproductionView: View {
    @State private var showingSettings = false
    @State private var configuration = ReviewToolbarConfiguration()
    var body: some View {
        NavigationStack {
            List {
                Button(AppText.localized("設定")) { showingSettings = true }
                    .accessibilityIdentifier("focus-scroll-settings")
            }.studyThemeSurface().navigationTitle("Scroll checks")
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form {
                    ForEach(0..<32, id: \.self) { index in Text("Parent row \(index + 1)") }
                    NavigationLink(AppText.localized("操作バーの設定")) {
                        ReviewToolbarSettingsView(configuration: $configuration)
                    }.accessibilityIdentifier("focus-scroll-toolbar")
                }
                .accessibilityIdentifier("focus-scroll-form")
                .studyThemeSurface().navigationTitle(AppText.localized("設定"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppText.localized("キャンセル")) { showingSettings = false }
                            .accessibilityIdentifier("focus-scroll-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppText.localized("保存")) { showingSettings = false }
                            .accessibilityIdentifier("focus-scroll-save")
                    }
                }
            }
        }
    }
}

/// Fourth comparison: the same inert-row parent owns configuration locally,
/// like SettingsView. The earlier passing scroll scene keeps its outer owner.
struct ToolbarLocalOwnerFocusReproductionApp: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("appearance") private var appearance = "system"
    init() {
        do { try UITestIsolation.prepare() }
        catch { fatalError("Could not initialize isolated UI test storage: \(error)") }
    }
    var body: some Scene {
        WindowGroup {
            StudyThemeContainer { ToolbarLocalOwnerFocusReproductionView() }
                .environment(\.locale, AppText.locale)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct ToolbarLocalOwnerFocusReproductionView: View {
    @State private var showingSettings = false
    var body: some View {
        NavigationStack {
            List {
                Button(AppText.localized("設定")) { showingSettings = true }
                    .accessibilityIdentifier("focus-owner-settings")
            }.studyThemeSurface().navigationTitle("Owner checks")
        }
        .sheet(isPresented: $showingSettings) { ToolbarLocalOwnerSettingsReproductionView() }
    }
}

struct ToolbarLocalOwnerSettingsReproductionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = ReviewToolbarConfiguration()
    var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<32, id: \.self) { index in Text("Parent row \(index + 1)") }
                NavigationLink(AppText.localized("操作バーの設定")) {
                    ReviewToolbarSettingsView(configuration: $configuration)
                }.accessibilityIdentifier("focus-owner-toolbar")
            }
            .accessibilityIdentifier("focus-owner-form")
            .studyThemeSurface().navigationTitle(AppText.localized("設定"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { dismiss() }
                        .accessibilityIdentifier("focus-owner-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("保存")) { dismiss() }
                        .accessibilityIdentifier("focus-owner-save")
                }
            }
        }
    }
}

/// Compare native control categories in otherwise identical scrolling parents.
/// These are diagnosis-only views, with no focus mutation or success injection.
protocol ToolbarFocusNativeControls: View { init() }

struct ToolbarNativeControlFocusReproductionApp<Controls: ToolbarFocusNativeControls>: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("appearance") private var appearance = "system"
    init() {
        do { try UITestIsolation.prepare() }
        catch { fatalError("Could not initialize isolated UI test storage: \(error)") }
    }
    var body: some Scene {
        WindowGroup {
            StudyThemeContainer { ToolbarNativeControlFocusReproductionView<Controls>() }
                .environment(\.locale, AppText.locale)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct ToolbarNativeControlFocusReproductionView<Controls: ToolbarFocusNativeControls>: View {
    @State private var showingSettings = false
    var body: some View {
        NavigationStack {
            List {
                Button(AppText.localized("設定")) { showingSettings = true }
                    .accessibilityIdentifier("focus-native-settings")
            }.studyThemeSurface().navigationTitle("Control checks")
        }
        .sheet(isPresented: $showingSettings) { ToolbarNativeControlSettingsReproductionView<Controls>() }
    }
}

struct ToolbarNativeControlSettingsReproductionView<Controls: ToolbarFocusNativeControls>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = ReviewToolbarConfiguration()
    var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<32, id: \.self) { index in Text("Parent row \(index + 1)") }
                Section { Controls() }
                NavigationLink(AppText.localized("操作バーの設定")) {
                    ReviewToolbarSettingsView(configuration: $configuration)
                }.accessibilityIdentifier("focus-native-toolbar")
            }
            .accessibilityIdentifier("focus-native-form")
            .studyThemeSurface().navigationTitle(AppText.localized("設定"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { dismiss() }
                        .accessibilityIdentifier("focus-native-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("保存")) { dismiss() }
                        .accessibilityIdentifier("focus-native-save")
                }
            }
        }
    }
}

struct ToolbarFocusTextControls: ToolbarFocusNativeControls {
    @State private var hold = "0"
    @State private var interval = "200"
    init() {}
    var body: some View {
        LabeledContent(AppText.localized("解答表示の長押し（ミリ秒）")) {
            TextField("0〜2000", text: $hold).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(width: 100).accessibilityIdentifier("focus-native-input-hold")
        }
        LabeledContent(AppText.localized("ボタンの連打防止（ミリ秒）")) {
            TextField("0〜1000", text: $interval).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(width: 100).accessibilityIdentifier("focus-native-input-interval")
        }
    }
}

struct ToolbarFocusSliderControls: ToolbarFocusNativeControls {
    @State private var zoom = 1.0
    @State private var size = 100.0
    init() {}
    var body: some View {
        VStack(alignment: .leading) {
            Text(AppText.localized("カードの拡大率: \(String(Int(zoom * 100)) + "%")"))
            Slider(value: $zoom, in: 0.5...2.5, step: 0.05)
                .accessibilityIdentifier("focus-native-slider-zoom")
        }
        Text(AppText.localized("ボタンの大きさ: \(String(Int(size)) + "%")"))
        Slider(value: $size, in: 10...200, step: 10).accessibilityIdentifier("focus-native-slider-size")
    }
}

struct ToolbarFocusStepperControls: ToolbarFocusNativeControls {
    @State private var timeout = 60
    @State private var timebox = 0
    @State private var zoom = 100
    init() {}
    var body: some View {
        Stepper(AppText.localized("通信のタイムアウト: \(timeout)秒"), value: $timeout, in: 10...1200, step: 10)
            .accessibilityIdentifier("focus-native-stepper-timeout")
        Stepper(AppText.localized("学習の区切り: \(timebox)分（0で無効）"), value: $timebox, in: 0...120)
            .accessibilityIdentifier("focus-native-stepper-timebox")
        Stepper(AppText.localized("画像の拡大率: \(zoom)%"), value: $zoom, in: 50...300, step: 10)
            .accessibilityIdentifier("focus-native-stepper-zoom")
    }
}
#endif
