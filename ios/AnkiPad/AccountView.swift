import SwiftUI

struct AccountView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var customServer = false
    @State private var endpoint = ""
    private var valid: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty &&
        (!customServer || (["https", "http"].contains(URL(string: endpoint)?.scheme ?? "") && URL(string: endpoint)?.host != nil))
    }
    var body: some View {
        NavigationStack {
            Form {
                if let account = model.account {
                    Section(AppText.localized("AnkiWebアカウント")) {
                        Text(account.username)
                        if let date = model.lastSync { LabeledContent(AppText.localized("最終同期"), value: date.formatted()) }
                        Button(AppText.localized("今すぐ同期")) { dismiss(); model.synchronize() }.disabled(model.busy)
                        Button(AppText.localized("ログアウト"), role: .destructive) { model.logout() }.accessibilityIdentifier("logout").disabled(model.busy)
                    }
                } else {
                    Section(AppText.localized("AnkiWebにログイン")) {
                        TextField(AppText.localized("メールアドレス"), text: $username)
                            .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().accessibilityIdentifier("login-username")
                        SecureField(AppText.localized("パスワード"), text: $password)
                            .textContentType(.password).accessibilityIdentifier("login-password")
                        Button(AppText.localized("ログインして同期")) {
                            let submittedPassword = password
                            password = ""
                            model.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                password: submittedPassword, endpoint: customServer ? endpoint : nil)
                        }.disabled(!valid || model.busy).accessibilityIdentifier("login-submit")
                        if model.isSyncing { ProgressView(model.syncStatus) }
                        Link(AppText.localized("AnkiWebのアカウントを作成"), destination: URL(string: "https://ankiweb.net/account/register")!)
                        Link(AppText.localized("パスワードを再設定"), destination: URL(string: "https://ankiweb.net/account/resetpw")!)
                    }
                    Section {
                        Toggle(AppText.localized("独自の同期サーバーを使う"), isOn: $customServer).accessibilityIdentifier("custom-server-toggle")
                        if customServer {
                            TextField("https://server.example/", text: $endpoint)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("custom-server-endpoint")
                        }
                    }
                    Section {
                        Text(AppText.localized("AnkiDroidと同じAnkiWebアカウントを使えます。パスワードは保存せず、ログイン後の認証情報をiPadのキーチェーンに保存します。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("account-form")
            .scrollDismissesKeyboard(.interactively)
            .disabled(model.busy)
            .studyThemeSurface().navigationTitle("AnkiWeb")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.busy ? AppText.localized("中止") : AppText.localized("閉じる")) { password = ""; if model.busy { model.cancelSync() } else { dismiss() } } } }
            .interactiveDismissDisabled(model.busy)
            .alert(AppText.localized("ログインできませんでした"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}
