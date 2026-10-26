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
                    Section("AnkiWebアカウント") {
                        Text(account.username)
                        if let date = model.lastSync { LabeledContent("最終同期", value: date.formatted()) }
                        Button("今すぐ同期") { dismiss(); model.synchronize() }.disabled(model.busy)
                        Button("ログアウト", role: .destructive) { model.logout() }.accessibilityIdentifier("logout").disabled(model.busy)
                    }
                } else {
                    Section("AnkiWebにログイン") {
                        TextField("メールアドレス", text: $username)
                            .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().accessibilityIdentifier("login-username")
                        SecureField("パスワード", text: $password)
                            .textContentType(.password).accessibilityIdentifier("login-password")
                        Button("ログインして同期") {
                            let submittedPassword = password
                            password = ""
                            model.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                password: submittedPassword, endpoint: customServer ? endpoint : nil)
                        }.disabled(!valid || model.busy).accessibilityIdentifier("login-submit")
                        if model.isSyncing { ProgressView(model.syncStatus) }
                        Link("AnkiWebのアカウントを作成", destination: URL(string: "https://ankiweb.net/account/register")!)
                        Link("パスワードを再設定", destination: URL(string: "https://ankiweb.net/account/resetpw")!)
                    }
                    Section {
                        Toggle("独自の同期サーバーを使う", isOn: $customServer).accessibilityIdentifier("custom-server-toggle")
                        if customServer {
                            TextField("https://server.example/", text: $endpoint)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("custom-server-endpoint")
                        }
                    }
                    Section {
                        Text("AnkiDroidと同じAnkiWebアカウントを使えます。パスワードは保存せず、ログイン後の認証情報をiPadのキーチェーンに保存します。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(model.busy)
            .navigationTitle("AnkiWeb")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.busy ? "中止" : "閉じる") { password = ""; if model.busy { model.cancelSync() } else { dismiss() } } } }
            .interactiveDismissDisabled(model.busy)
            .alert("ログインできませんでした", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("閉じる", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}
