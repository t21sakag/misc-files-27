import SwiftUI

struct BrowserForgetRequest: Identifiable {
    let id = UUID()
    let cardIDs: [String]
    let profileID: String
}

@MainActor struct BrowserForgetCardsView: View {
    @ObservedObject var model: StudyModel
    let request: BrowserForgetRequest
    let didApply: () -> Void
    private let engine: Engine
    private let preferenceKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var options = BrowserForgetOptions()
    @State private var loaded = false
    @State private var busy = false
    @State private var active = true
    @State private var error: String?

    init(model: StudyModel, request: BrowserForgetRequest, didApply: @escaping () -> Void) {
        self.model = model; self.request = request; self.didApply = didApply
        engine = model.engine; preferenceKey = model.profilePreferenceKey("browserForgetOptions")
    }
    var body: some View {
        NavigationStack {
            Form {
                Text(AppText.localized("\(request.cardIDs.count)枚")).accessibilityIdentifier("browser-forget-count")
                Toggle(AppText.localized("元の新規カードの位置に戻す"), isOn: $options.restorePosition)
                    .accessibilityIdentifier("browser-forget-restore")
                Toggle(AppText.localized("解答回数と忘却回数をリセット"), isOn: $options.resetCounts)
                    .accessibilityIdentifier("browser-forget-counts")
                if busy { ProgressView() }
            }
            .disabled(!loaded || busy).studyThemeSurface().navigationTitle(AppText.localized("新規カードに戻す"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { active = false; dismiss() }
                        .disabled(busy).accessibilityIdentifier("browser-forget-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("新規カードに戻す"), role: .destructive) { submit() }
                        .disabled(!loaded || busy).accessibilityIdentifier("browser-forget-apply")
                }
            }
            .interactiveDismissDisabled(busy).onDisappear { active = false }
            .task {
                do {
                    try requireProfile()
                    options = try BrowserForgetOptions.load(key: preferenceKey)
                    _ = try options.arguments(cardIDs: request.cardIDs)
                    loaded = true
                } catch { self.error = error.localizedDescription }
            }
            .alert(AppText.localized("変更できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func requireProfile() throws {
        guard model.currentProfile.id == request.profileID else {
            throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
        }
    }
    private func submit() {
        guard loaded, !busy, active else { return }
        busy = true
        let snapshot = options
        Task {
            defer { busy = false }
            do {
                try requireProfile()
                _ = try snapshot.arguments(cardIDs: request.cardIDs)
                // Android saves the options when the user confirms, even if a
                // later scheduling operation fails. Cancel never writes them.
                try snapshot.save(key: preferenceKey)
                try await engine.forgetBrowserCards(request.cardIDs, options: snapshot)
                guard active, model.currentProfile.id == request.profileID else { return }
                model.refreshAfterEditing(); didApply(); active = false; dismiss()
            } catch { if active { self.error = error.localizedDescription } }
        }
    }
}
