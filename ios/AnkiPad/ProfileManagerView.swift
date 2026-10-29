import SwiftUI

struct ProfileManagerView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingName = false
    @State private var name = ""
    @State private var renaming: StudyProfile?
    @State private var deleting: StudyProfile?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.profileRegistry.profiles) { profile in
                        Button { perform { try await model.switchProfile(profile.id) } } label: {
                            HStack {
                                Text(profile.name).foregroundStyle(.primary)
                                Spacer()
                                if profile.id == model.currentProfileID { Image(systemName: "checkmark").accessibilityLabel(AppText.localized("使用中")) }
                            }
                        }
                        .accessibilityIdentifier("profile-" + profile.id)
                        .contextMenu {
                            Button(AppText.localized("名前を変更")) { renaming = profile; name = profile.name; editingName = true }
                            Button(AppText.localized("削除"), role: .destructive) { deleting = profile }.disabled(profile.id == model.currentProfileID)
                        }
                    }
                } footer: {
                    Text(AppText.localized("デッキ・メディア・バックアップ・AnkiWebアカウントはプロファイルごとに保存します。表示とスワイプの設定は共通です。"))
                }
                if model.busy { ProgressView(AppText.localized("切り替えています…")) }
            }
            .disabled(model.busy || !model.profilesReady)
            .accessibilityIdentifier("profiles-form").studyThemeSurface().navigationTitle(AppText.localized("プロファイル"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() }.disabled(model.busy).accessibilityIdentifier("profiles-close") }
                ToolbarItem(placement: .primaryAction) {
                    Button { renaming = nil; name = ""; editingName = true } label: { Image(systemName: "plus") }
                        .disabled(model.busy || !model.profilesReady).accessibilityIdentifier("profile-add")
                }
            }
            .interactiveDismissDisabled(model.busy)
            .alert(renaming == nil ? AppText.localized("プロファイルを追加") : AppText.localized("名前を変更"), isPresented: $editingName) {
                TextField(AppText.localized("名前"), text: $name).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("profile-name")
                Button(AppText.localized("保存")) {
                    if let renaming { perform { try model.renameProfile(renaming, name: name) } }
                    else { perform { let id = try model.addProfile(name); try await model.switchProfile(id) } }
                }.accessibilityIdentifier("profile-save")
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
            .alert(AppText.localized("プロファイルを削除しますか？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { profile in
                Button(AppText.localized("削除"), role: .destructive) { deleting = nil; perform { try await model.deleteProfile(profile) } }.accessibilityIdentifier("profile-delete-confirm")
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            } message: { profile in Text(AppText.localized("「\(profile.name)」のデッキ・メディア・バックアップ・ログイン情報を削除します。")) }
            .alert(AppText.localized("プロファイルを変更できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func perform(_ action: @escaping () async throws -> Void) {
        Task { do { try await action() } catch { self.error = error.localizedDescription } }
    }
}
