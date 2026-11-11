import SwiftUI

struct TagSelectionRequest: Identifiable {
    let id = UUID()
    let dialogType: TagSelectionDialogType
    let noteIDs: [String]
    let extraCheckedTags: [String]
}

@MainActor struct TagSelectionView: View {
    @ObservedObject var model: StudyModel
    let dialogType: TagSelectionDialogType
    let noteIDs: [String]
    let extraCheckedTags: [String]
    let onConfirm: ([String], [String]) -> Void
    private let engine: Engine
    private let profileID: String
    @Environment(\.dismiss) private var dismiss
    @State private var state: TagSelectionState
    @State private var loaded = false
    @State private var busy = false
    @State private var active = true
    @State private var addingTag = false
    @State private var error: String?

    init(model: StudyModel,
         dialogType: TagSelectionDialogType = .editTags,
         noteIDs: [String] = [],
         extraCheckedTags: [String] = [],
         engine expectedEngine: Engine? = nil,
         profileID expectedProfileID: String? = nil,
         onConfirm: @escaping ([String], [String]) -> Void) {
        self.model = model
        self.dialogType = dialogType
        self.noteIDs = noteIDs
        self.extraCheckedTags = extraCheckedTags
        self.onConfirm = onConfirm
        self.engine = expectedEngine ?? model.engine
        self.profileID = expectedProfileID ?? model.currentProfileID
        _state = State(initialValue: TagSelectionState(
            dialogType: dialogType,
            allTags: [],
            checkedTags: [],
            uncheckedTags: nil,
            extraCheckedTags: extraCheckedTags
        ))
    }

    private var rows: [TagSelectionRow] { state.visibleRows() }
    private var allChecked: Bool {
        !state.allTagList.isEmpty && state.checkedTagList.count == state.allTagList.count
    }

    var body: some View {
        NavigationStack {
            List {
                if !loaded {
                    ProgressView()
                } else {
                    ForEach(rows) { row in
                        HStack {
                            if row.hasChildren {
                                Button {
                                    state.toggleExpanded(row.tag)
                                } label: {
                                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(row.isExpanded ? AppText.localized("折りたたむ") : AppText.localized("展開"))
                                .accessibilityIdentifier("tag-picker-expand-" + row.tag)
                            }
                            Button {
                                state.toggleRow(row.tag)
                            } label: {
                                HStack {
                                    Text(row.tag).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: iconName(for: row.checkState))
                                }.frame(maxWidth: .infinity).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityValue(valueLabel(for: row.checkState))
                            .accessibilityIdentifier("tag-picker-choice-" + row.tag)
                        }.padding(.leading, CGFloat(row.level) * 12)
                    }
                    if rows.isEmpty {
                        Text(AppText.localized("タグがありません"))
                    }
                }
            }
            .accessibilityIdentifier("tag-picker-list")
            .searchable(text: $state.searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: AppText.localized("タグを検索"))
            .disabled(busy || model.busy)
            .studyThemeSurface()
            .navigationTitle(AppText.localized("タグを編集"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) {
                        active = false
                        dismiss()
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("tag-picker-cancel")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        _ = state.toggleAllCheckedStatuses()
                    } label: {
                        Image(systemName: allChecked ? "checkmark.square.fill" : "checkmark.square")
                    }
                    .disabled(!loaded || busy || model.busy || state.allTagList.isEmpty)
                    .accessibilityLabel(allChecked ? AppText.localized("選択を解除") : AppText.localized("すべて選択"))
                    .accessibilityIdentifier("tag-picker-toggle-all")

                    if dialogType.showsAddButton {
                        Button {
                            addingTag = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!loaded || busy || model.busy)
                        .accessibilityLabel(AppText.localized("新しいタグ名"))
                        .accessibilityIdentifier("tag-picker-add")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("適用")) {
                        confirm()
                    }
                    .disabled(!loaded || busy || model.busy)
                    .accessibilityIdentifier("tag-picker-apply")
                }
            }
            .sheet(isPresented: $addingTag) {
                TagCreationForm { rawName in
                    guard let added = state.addTag(rawName) else {
                        throw EngineError(message: AppText.localized("空白や空の階層を含まないタグ名を入力してください。"))
                    }
                    return added
                }
            }
            .alert(AppText.localized("タグを変更できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task { await load() }
        }
    }

    private func iconName(for checkState: TagSelectionCheckState) -> String {
        switch checkState {
        case .checked: return "checkmark.square.fill"
        case .indeterminate: return "minus.square.fill"
        case .unchecked: return "square"
        }
    }

    private func valueLabel(for checkState: TagSelectionCheckState) -> String {
        switch checkState {
        case .checked: return AppText.localized("選択中")
        case .indeterminate: return AppText.localized("すべて")
        case .unchecked: return AppText.localized("未選択")
        }
    }

    private func ensureProfile() throws {
        guard active, model.profilesReady, model.currentProfileID == profileID, model.engine === engine else {
            throw EngineError(message: AppText.localized("プロファイルが変わりました。画面を開き直してください。"))
        }
    }

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            try ensureProfile()
            let engine = self.engine
            let ids = self.noteIDs
            let extras = self.extraCheckedTags
            let type = self.dialogType
            let loadedState = try await engine.loadTagSelectionState(
                noteIDs: ids,
                extraCheckedTags: extras,
                dialogType: type
            )
            try ensureProfile()
            state = loadedState
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func confirm() {
        guard loaded, !busy, !model.busy else { return }
        let checked = state.checkedTagList
        let partial = state.partiallySelectedTagList
        guard !noteIDs.isEmpty else {
            do {
                try ensureProfile()
                active = false
                onConfirm(checked, partial)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            return
        }
        busy = true
        let engine = self.engine
        let ids = self.noteIDs
        Task {
            defer { busy = false }
            do {
                try ensureProfile()
                try await engine.backup()
                try ensureProfile()
                try await engine.applyBatchTagSelection(
                    noteIDs: ids,
                    checkedTags: checked,
                    partiallySelectedTags: partial
                )
                try ensureProfile()
                active = false
                onConfirm(checked, partial)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

@MainActor private struct TagCreationForm: View {
    let create: (String) throws -> String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(AppText.localized("新しいタグ名"), text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("tag-picker-name")
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("tag-picker-create-error")
                }
            }
            .accessibilityIdentifier("tag-picker-create-form")
            .studyThemeSurface()
            .navigationTitle(AppText.localized("新しいタグ名"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { dismiss() }
                        .accessibilityIdentifier("tag-picker-create-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("追加")) { submit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("tag-picker-create-confirm")
                }
            }
        }
    }

    private func submit() {
        error = nil
        do {
            _ = try create(name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
