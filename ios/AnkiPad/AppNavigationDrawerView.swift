import SwiftUI

enum AppNavigationChoice: String, CaseIterable, Identifiable {
    case decks, profiles, browser, sharedDecks, statistics, noteTypes, settings, maintenance, account
    var id: String { rawValue }
    var title: String {
        switch self {
        case .decks: "デッキ一覧"
        case .profiles: "プロファイル"
        case .browser: "カードブラウザー"
        case .sharedDecks: "共有デッキを取得"
        case .statistics: "統計"
        case .noteTypes: "ノートタイプ"
        case .settings: "設定"
        case .maintenance: "バックアップとメンテナンス"
        case .account: "AnkiWebアカウント"
        }
    }
}
struct AppNavigationDrawerView: View {
    @ObservedObject var model: StudyModel
    var body: some View {
        NavigationStack {
            List {
                ForEach(AppNavigationChoice.allCases) { choice in
                    Button(choice.title) {
                        model.pendingNavigationChoice = choice
                        model.showingNavigationDrawer = false
                    }.disabled(model.busy).accessibilityIdentifier("destination-" + choice.rawValue)
                }
                NavigationLink("ライセンスとソース") { OpenSourceLicensesView() }
            }
            .studyThemeSurface().navigationTitle("ナビゲーション")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { model.showingNavigationDrawer = false } } }
        }
    }
}
extension StudyModel {
    func finishNavigationSelection() {
        guard let choice = pendingNavigationChoice else { return }
        pendingNavigationChoice = nil
        guard !busy else { showCardToast("処理が終わってからもう一度選んでください。", short: true); return }
        switch choice {
        case .decks: leave()
        case .profiles: leave(); showingProfiles = true
        case .browser: browserSearch = ""; showingBrowser = true
        case .sharedDecks: leave(); showingSharedDecks = true
        case .statistics: backendPage = BackendPageRequest(path: "graphs", title: "統計")
        case .noteTypes: showingNoteTypes = true
        case .settings: showingSettings = true
        case .maintenance: showingMaintenance = true
        case .account: showingAccount = true
        }
    }
}
