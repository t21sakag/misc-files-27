import SwiftUI

enum AppNavigationChoice: String, CaseIterable, Identifiable {
    case decks, profiles, browser, sharedDecks, statistics, noteTypes, settings, maintenance, account
    var id: String { rawValue }
    var title: String {
        switch self {
        case .decks: AppText.localized("デッキ一覧")
        case .profiles: AppText.localized("プロファイル")
        case .browser: AppText.localized("カードブラウザー")
        case .sharedDecks: AppText.localized("共有デッキを取得")
        case .statistics: AppText.localized("統計")
        case .noteTypes: AppText.localized("ノートタイプ")
        case .settings: AppText.localized("設定")
        case .maintenance: AppText.localized("バックアップとメンテナンス")
        case .account: AppText.localized("AnkiWebアカウント")
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
                NavigationLink(AppText.localized("ライセンスとソース")) { OpenSourceLicensesView() }
            }
            .studyThemeSurface().navigationTitle(AppText.localized("ナビゲーション"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { model.showingNavigationDrawer = false } } }
        }
    }
}
extension StudyModel {
    func finishNavigationSelection() {
        guard let choice = pendingNavigationChoice else { return }
        pendingNavigationChoice = nil
        guard !busy else { showCardToast(AppText.localized("処理が終わってからもう一度選んでください。"), short: true); return }
        switch choice {
        case .decks: leave()
        case .profiles: leave(); showingProfiles = true
        case .browser: browserSearch = ""; showingBrowser = true
        case .sharedDecks: leave(); showingSharedDecks = true
        case .statistics: backendPage = BackendPageRequest(path: "graphs", title: AppText.localized("統計"))
        case .noteTypes: showingNoteTypes = true
        case .settings: showingSettings = true
        case .maintenance: showingMaintenance = true
        case .account: showingAccount = true
        }
    }
}
