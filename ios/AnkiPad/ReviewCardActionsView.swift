import SwiftUI

enum ReviewCardAction: String { case tags, due, reset }
struct ReviewCardActionRequest: Identifiable {
    let id = UUID()
    let cardID: String
    let noteID: String
    let action: ReviewCardAction
}
struct ReviewCardActionsView: View {
    @ObservedObject var model: StudyModel
    let request: ReviewCardActionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var tags = ""
    @State private var days = "0"
    @State private var log = true
    @State private var resetCounts = false
    @State private var restorePosition = true
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    private var title: String { switch request.action { case .tags: AppText.localized("タグを編集"); case .due: AppText.localized("期日を変更"); case .reset: AppText.localized("新規カードに戻す") } }
    var body: some View {
        NavigationStack {
            Form {
                switch request.action {
                case .tags:
                    TextField(AppText.localized("タグ（空白で区切る）"), text: $tags).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("card-action-tags")
                case .due:
                    TextField(AppText.localized("今日からの日数（例: 3、3-7）"), text: $days).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(AppText.localized("範囲を指定すると、その範囲にカードを割り振ります。末尾に ! を付けると間隔も日数に合わせて変更します。"))
                case .reset:
                    Toggle(AppText.localized("元の新規カードの位置に戻す"), isOn: $restorePosition)
                    Toggle(AppText.localized("解答回数と忘却回数をリセット"), isOn: $resetCounts)
                    Toggle(AppText.localized("変更を学習履歴に記録"), isOn: $log)
                }
                if busy { ProgressView() }
            }
            .disabled(busy || !loaded)
            .studyThemeSurface().navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("適用")) { save() }.disabled(busy || !loaded).accessibilityIdentifier("card-action-apply") }
            }
            .task {
                do {
                    if request.action == .tags {
                        let note = try await model.engine.call("NotesService.GetNote", ["nid": request.noteID])
                        tags = (note["tags"] as? [String] ?? []).joined(separator: " ")
                    } else if request.action == .reset {
                        let defaults = try await model.engine.call("SchedulerService.ScheduleCardsAsNewDefaults", ["context": "REVIEWER"])
                        restorePosition = defaults["restorePosition"] as? Bool ?? false
                        resetCounts = defaults["resetCounts"] as? Bool ?? false
                    }
                    loaded = true
                } catch { self.error = error.localizedDescription }
            }
            .alert(AppText.localized("変更できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(AppText.localized("閉じる"), role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.engine.backup()
                switch request.action {
                case .tags:
                    var note = try await model.engine.call("NotesService.GetNote", ["nid": request.noteID])
                    note["tags"] = tags.split(whereSeparator: \.isWhitespace).map(String.init)
                    _ = try await model.engine.call("NotesService.UpdateNotes", ["notes": [note]])
                case .due: try await model.engine.setDue([request.cardID], days: days)
                case .reset:
                    _ = try await model.engine.call("SchedulerService.ScheduleCardsAsNew", ["cardIds": [request.cardID], "log": log, "restorePosition": restorePosition, "resetCounts": resetCounts, "context": "REVIEWER"])
                }
                model.refreshAfterEditing()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
