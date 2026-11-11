import Foundation
#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
#endif
#if canImport(Security)
import Security
#endif

enum ReviewerFrameStyle: String, CaseIterable, Identifiable {
    case none, card, box
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: AppText.localized("枠なし")
        case .card: AppText.localized("カード枠")
        case .box: AppText.localized("ボックス枠")
        }
    }
}

enum ReviewerToolbarPosition: String, CaseIterable, Identifiable {
    case top, bottom, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: AppText.localized("上部")
        case .bottom: AppText.localized("下部")
        case .none: AppText.localized("非表示")
        }
    }
}

#if canImport(SwiftUI)
struct AppLanguageSearchView: View {
    @Binding var selection: AppLanguageChoice
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var filtered: [AppLanguageChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AppLanguageChoice.allCases }
        return AppLanguageChoice.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }
    var body: some View {
        List {
            ForEach(filtered) { choice in
                Button {
                    selection = choice
                    dismiss()
                } label: {
                    HStack {
                        Text(choice.title).foregroundStyle(.primary)
                        Spacer()
                        if choice == selection { Image(systemName: "checkmark") }
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("language-choice-" + choice.rawValue)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: AppText.localized("言語を検索"))
        .studyThemeSurface()
        .navigationTitle(AppText.localized("アプリの言語"))
    }
}

struct AppHelpView: View {
    var body: some View {
        List {
            Section(AppText.localized("基本的な使い方")) {
                Text(AppText.localized("デッキをタップして学習を開始し、問題を確認したら「解答を表示」をタップして評価ボタン（もう一度・難しい・普通・簡単）を選びます。"))
                Text(AppText.localized("右上の「＋」から新しいノートや画像穴埋めカード、フィルターデッキを作成できます。"))
            }
            Section(AppText.localized("検索とブラウザー")) {
                Text(AppText.localized("カードブラウザーでは deck:、tag:、note:、flag:、is:due、is:new、is:review、prop:ivl>=10 などの検索式を使えます。"))
            }
            Section(AppText.localized("同期とバックアップ")) {
                Text(AppText.localized("AnkiWebアカウントまたは独自の同期サーバーでコレクションとメディアを同期できます。変更前にはローカルバックアップが自動作成されます。"))
            }
            Section(AppText.localized("オンラインマニュアル")) {
                Link(AppText.localized("AnkiDroid マニュアル"), destination: URL(string: "https://docs.ankidroid.org/")!)
                    .accessibilityIdentifier("help-ankidroid-manual")
                Link(AppText.localized("Anki マニュアル"), destination: URL(string: "https://docs.ankiweb.net/")!)
                    .accessibilityIdentifier("help-anki-manual")
            }
        }
        .studyThemeSurface()
        .navigationTitle(AppText.localized("ヘルプと使い方"))
    }
}

struct AppSupportView: View {
    var body: some View {
        List {
            Section(AppText.localized("AnkiDroid プロジェクト")) {
                Text(AppText.localized("このアプリはオープンソースの AnkiDroid（GPL-3.0-or-later）および Anki バックエンドを基に構築されています。"))
                Link(AppText.localized("AnkiDroid 公式サイト"), destination: URL(string: "https://ankidroid.org/")!)
                    .accessibilityIdentifier("support-ankidroid-site")
                Link(AppText.localized("OpenCollective で AnkiDroid を寄付支援"), destination: URL(string: "https://opencollective.com/ankidroid")!)
                    .accessibilityIdentifier("support-ankidroid-donate")
            }
        }
        .studyThemeSurface()
        .navigationTitle(AppText.localized("AnkiDroidを支援"))
    }
}

struct AppAboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    private var commit: String {
        Bundle.main.infoDictionary?["AnkiPadSourceCommit"] as? String ?? "development"
    }
    var body: some View {
        List {
            Section(AppText.localized("バージョン情報")) {
                LabeledContent(AppText.localized("バージョン"), value: "\(version) (\(build))")
                    .accessibilityIdentifier("about-version")
                LabeledContent(AppText.localized("ソースコミット"), value: commit)
                    .accessibilityIdentifier("about-commit")
                LabeledContent(AppText.localized("対応ベースライン"), value: "AnkiDroid v2.26.0alpha7")
                    .accessibilityIdentifier("about-baseline")
            }
            Section {
                NavigationLink(AppText.localized("ヘルプと使い方")) { AppHelpView() }
                    .accessibilityIdentifier("about-help")
                NavigationLink(AppText.localized("AnkiDroidを支援")) { AppSupportView() }
                    .accessibilityIdentifier("about-support")
                NavigationLink(AppText.localized("ライセンスとソース")) { OpenSourceLicensesView() }
                    .accessibilityIdentifier("about-licenses")
            }
        }
        .studyThemeSurface()
        .navigationTitle(AppText.localized("このアプリについて"))
    }
}
#endif

enum CustomSyncCertificateStore {
    private static let key = "customSyncCertificateDER"
    static func summary(_ defaults: UserDefaults = .standard) -> String? {
        guard let data = defaults.data(forKey: key) else { return nil }
        #if canImport(Security)
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else { return nil }
        let subject = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Certificate"
        return subject + " (\(data.count) bytes)"
        #else
        guard data.count >= 4, data[data.startIndex] == 0x30 else { return nil }
        return "Certificate (\(data.count) bytes)"
        #endif
    }
    static func save(_ rawData: Data, defaults: UserDefaults = .standard) throws -> String {
        let der: Data
        if let text = String(data: rawData, encoding: .utf8),
           let begin = text.range(of: "-----BEGIN CERTIFICATE-----"),
           let end = text.range(of: "-----END CERTIFICATE-----") {
            let body = text[begin.upperBound..<end.lowerBound]
                .components(separatedBy: .whitespacesAndNewlines).joined()
            guard let decoded = Data(base64Encoded: body) else {
                throw EngineError(message: AppText.localized("証明書ファイルを読み込めませんでした。"))
            }
            der = decoded
        } else {
            der = rawData
        }
        #if canImport(Security)
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            throw EngineError(message: AppText.localized("有効なX.509証明書ではありません。"))
        }
        defaults.set(der, forKey: key)
        return (SecCertificateCopySubjectSummary(cert) as String?) ?? "Certificate"
        #else
        guard der.count >= 4, der[der.startIndex] == 0x30 else {
            throw EngineError(message: AppText.localized("有効なX.509証明書ではありません。"))
        }
        defaults.set(der, forKey: key)
        return "Certificate"
        #endif
    }
    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
