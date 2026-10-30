import Foundation
import SwiftUI

@MainActor final class SharedInboxController: ObservableObject {
    @Published private(set) var entries: [SharedInboxEntry] = []
    @Published private(set) var invalid: [UUID] = []
    @Published private(set) var available = false
    @Published var error: String?
    private var inbox: SharedInbox?
    private var active = Set<UUID>()
    private var deferred = Set<UUID>()
    private var generation = UUID()
    var nextAutomaticEntry: SharedInboxEntry? {
        entries.first { !deferred.contains($0.id) && $0.transfer.attachments.count <= 1 }
    }
    func refresh() {
        let request = UUID(); generation = request
        guard let container = SharedGroup.container() else { available = false; return }
        available = true
        let inbox = SharedInbox(root: container.appendingPathComponent("IncomingShares", isDirectory: true))
        self.inbox = inbox
        let language = AppText.language
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    // Language propagation must not hide already received content.
                    try? SharedClientSettings.save(language: language, in: container)
                    return try inbox.scan()
                }.value
                guard generation == request else { return }
                entries = result.entries.filter { !active.contains($0.id) }
                invalid = result.invalid
            } catch {
                guard generation == request else { return }
                self.error = AppText.localized("共有の受信トレイを読み込めませんでした。")
            }
        }
    }
    func begin(_ entry: SharedInboxEntry) -> SharedInboxReceipt? {
        guard let inbox, !active.contains(entry.id) else { return nil }
        active.insert(entry.id)
        entries.removeAll { $0.id == entry.id }
        return SharedInboxReceipt(id: entry.id, inbox: inbox) { [weak self] id, accepted in
            guard let self else { return }
            active.remove(id)
            if accepted { deferred.remove(id) } else { deferred.insert(id) }
            refresh()
        }
    }
    func remove(_ id: UUID) {
        guard let inbox, !active.contains(id) else { return }
        Task {
            do {
                try await Task.detached(priority: .utility) { try inbox.finish(id) }.value
                deferred.remove(id); refresh()
            } catch { self.error = AppText.localized("共有内容を削除できませんでした。") }
        }
    }
}

struct SharedInboxView: View {
    @ObservedObject var inbox: SharedInboxController
    let profileName: String
    let open: (SharedInboxEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: UUID?
    var body: some View {
        NavigationStack {
            List {
                Section(AppText.localized("取り込み先")) { Text(profileName) }
                if !inbox.available {
                    Text(AppText.localized("共有の保存先を開けませんでした。アプリを開き直しても改善しない場合は再署名してください。"))
                } else if inbox.entries.isEmpty && inbox.invalid.isEmpty {
                    Text(AppText.localized("まだ受信した内容がありません。"))
                }
                ForEach(inbox.entries) { entry in
                    Section {
                        if let text = entry.transfer.text {
                            if !text.subject.isEmpty { Text(text.subject).font(.headline) }
                            Text(text.text).lineLimit(5)
                        }
                        ForEach(entry.transfer.attachments, id: \.storedName) { Text($0.originalName) }
                        Button(entry.transfer.attachments.isEmpty ? AppText.localized("ノートとして開く") : AppText.localized("取り込みを確認")) { open(entry) }
                            .disabled(entry.transfer.attachments.count > 1)
                            .accessibilityIdentifier("shared-inbox-open-" + entry.id.uuidString)
                        Button(AppText.localized("削除"), role: .destructive) { deleting = entry.id }
                    }
                }
                ForEach(inbox.invalid, id: \.self) { id in
                    Section {
                        Text(AppText.localized("読み込めない共有内容があります。"))
                        Button(AppText.localized("削除"), role: .destructive) { deleting = id }
                    }
                }
            }
            .studyThemeSurface().navigationTitle(AppText.localized("共有の受信トレイ"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() } } }
            .task { inbox.refresh() }
            .confirmationDialog(AppText.localized("この共有内容を削除しますか？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let id = deleting { Button(AppText.localized("削除"), role: .destructive) { inbox.remove(id); deleting = nil } }
                Button(AppText.localized("キャンセル"), role: .cancel) { deleting = nil }
            }
            .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { inbox.error != nil }, set: { if !$0 { inbox.error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { inbox.error = nil }
            } message: { Text(inbox.error ?? "") }
        }
    }
}
