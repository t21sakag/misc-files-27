import SwiftUI

struct FlagNamesView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(1...7, id: \.self) { code in
                NavigationLink {
                    FlagNameEditorView(model: model, code: code, name: model.flagLabels.name(code))
                } label: {
                    Label(model.flagLabels.name(code), systemImage: "flag.fill")
                        .foregroundStyle(Self.color(code))
                }.accessibilityIdentifier("flag-name-\(code)")
            }
        }
        .disabled(!loaded || model.busy)
        .studyThemeSurface().navigationTitle(AppText.localized("フラグ名を変更"))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppText.localized("閉じる")) { dismiss() }
                    .disabled(model.busy).accessibilityIdentifier("flag-names-close")
            }
        }
        .task {
            do { try await model.loadFlagLabels(); loaded = true }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    static func color(_ code: Int) -> Color {
        [.gray, .red, .orange, .green, .blue, .pink, .cyan, .purple][min(7, max(0, code))]
    }
}

private struct FlagNameEditorView: View {
    @ObservedObject var model: StudyModel
    let code: Int
    @State private var name: String
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(model: StudyModel, code: Int, name: String) {
        self.model = model; self.code = code; _name = State(initialValue: name)
    }
    var body: some View {
        Form {
            HStack {
                TextField(AppText.localized("名前"), text: $name)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("flag-name-text")
                Button { name = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).accessibilityLabel(AppText.localized("入力を消去"))
                    .accessibilityIdentifier("flag-name-clear")
            }
        }
        .disabled(busy || model.busy)
        .studyThemeSurface().navigationTitle(AppText.localized("フラグ名を変更"))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppText.localized("キャンセル")) { dismiss() }.disabled(busy || model.busy).accessibilityIdentifier("flag-name-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(AppText.localized("保存")) { save() }.disabled(busy || model.busy).accessibilityIdentifier("flag-name-save")
            }
        }
        .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func save() {
        guard !busy, !model.busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await model.renameFlag(code, name: name); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
