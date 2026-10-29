import SwiftUI

struct SharedTextEntryView: View {
    let continueToEditor: (IncomingNoteDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var text = ""
    @State private var tags = ""
    @State private var isHTML = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("件名（任意）")) {
                    TextField(AppText.localized("表面"), text: $subject).accessibilityIdentifier("shared-text-subject")
                }
                Section(AppText.localized("テキスト")) {
                    PasteButton(payloadType: String.self) { values in
                        text = values.joined(separator: "\n")
                    }.accessibilityIdentifier("shared-text-paste")
                    TextEditor(text: $text).frame(minHeight: 180).accessibilityIdentifier("shared-text-body")
                    Text(AppText.localized("件名が空ならテキストを表面に入れます。件名がある場合は、件名を表面、テキストを裏面に入れます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextField(AppText.localized("タグ（空白で区切る）"), text: $tags)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle(AppText.localized("HTMLとして取り込む"), isOn: $isHTML)
                    Text(AppText.localized("次の編集画面でノートタイプとデッキを確認してから保存します。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .studyThemeSurface().navigationTitle(AppText.localized("テキストからノートを追加"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("編集を続ける")) {
                        guard !submitted else { return }
                        submitted = true
                        continueToEditor(IncomingNoteDraft(subject: subject, text: text,
                                                          tags: tags.isEmpty ? nil : tags, isHTML: isHTML))
                    }.disabled(submitted || (subject.isEmpty && text.isEmpty)).accessibilityIdentifier("shared-text-continue")
                }
            }
        }
    }
}
