import SwiftUI

struct BrowserView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("relativeCardBrowserFontSize") private var fontPercent = 100
    @AppStorage("card_browser_show_media_filenames") private var showMediaFilenames = false
    @ScaledMetric(relativeTo: .body) private var primarySize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var secondarySize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var metadataSize: CGFloat = 11
    private var fontScale: CGFloat { CGFloat(max(10, min(200, fontPercent))) / 100 }
    @State private var query: String
    @State private var config = BrowserConfiguration(notesMode: false, columns: ["noteFld", "template", "cardDue", "deck"], sortColumn: "noteFld", backwards: false, savedSearches: [:])
    @State private var columns: [BrowserColumn] = []
    @State private var tags: [String] = []
    @State private var types: [NamedID] = []
    @State private var loaded = false
    @State private var completedQuery = ""
    @State private var ids: [String] = []
    @State private var rows: [BrowserCard] = []
    @State private var selected: Set<String> = []
    @State private var editMode = EditMode.inactive
    @State private var editor: EditorRequest?
    @State private var changingType: BackendPageRequest?
    @State private var preview: CardPreviewRequest?
    @State private var findReplace: FindReplaceRequest?
    @State private var selectionExport: SelectionExportRequest?
    @State private var busy = false
    @State private var error: String?
    @State private var deleteConfirm = false
    @State private var tagPrompt = false
    @State private var tagText = ""
    @State private var duePrompt = false
    @State private var days = ""
    @State private var movePrompt = false
    @State private var columnPicker = false
    @State private var saveSearchPrompt = false
    @State private var searchName = ""
    @State private var manageSearches = false
    @State private var managingTags = false
    @State private var repositionPrompt = false
    @State private var position = 1
    @State private var positionStep = 1
    @State private var randomPosition = false
    @State private var shiftPosition = true
    @State private var revision = 0
    init(model: StudyModel) { self.model = model; _query = State(initialValue: model.browserSearch) }
    var body: some View {
        NavigationStack { dialogs }
            .environment(\.editMode, $editMode)
            .task { await initialize() }
            .onDisappear { UserDefaults.standard.set(query, forKey: model.profilePreferenceKey("lastBrowserSearch")) }
            .task(id: "\(loaded)-\(query)-\(revision)-\(config.notesMode)-\(showMediaFilenames)") { await search() }
    }
    private var list: some View {
        List(selection: $selected) {
            Section {
                ForEach(rows) { row in
                    Group {
                        if editMode.isEditing { rowView(row) }
                        else { Button { edit(row) } label: { rowView(row) }.accessibilityIdentifier("browser-card-\(row.id)") }
                    }
                    .tag(row.id)
                    .contextMenu {
                        Button("編集") { edit(row) }
                        Button("プレビュー") { preview = CardPreviewRequest(ids: row.cardIDs) }.disabled(row.cardIDs.isEmpty)
                        Button(row.suspended ? "保留を解除" : "保留") { mutate { if row.suspended { try await model.engine.restoreCards(row.cardIDs) } else { try await model.engine.suspend(row.cardIDs) } } }
                        Button("今日は表示しない") { mutate { try await model.engine.bury(row.cardIDs) } }
                    }
                }
                if rows.count < ids.count { Button("さらに表示（\(rows.count) / \(ids.count)）", action: loadMore).disabled(busy) }
            } header: { Text("\(ids.count)\(config.notesMode ? "ノート" : "枚") · \(selected.count)件選択中").accessibilityIdentifier("browser-results").accessibilityValue(completedQuery) }
            if busy { ProgressView() }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "検索（deck:、tag:、is:due など）")
        .studyThemeSurface()
        .navigationTitle(config.notesMode ? "ノートブラウザー" : "カードブラウザー")
        .toolbar { toolbar }
    }
    @ViewBuilder private func rowView(_ row: BrowserCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if row.suspended { Image(systemName: "pause.circle").foregroundStyle(.orange) }
                if row.flag > 0 { Image(systemName: "flag.fill").foregroundStyle(flagColor(row.flag)) }
                Text(row.front.isEmpty ? "（空のフィールド）" : row.front).font(.system(size: primarySize * fontScale)).lineLimit(2).foregroundStyle(.primary)
                    .accessibilityIdentifier("browser-front-\(row.id)")
            }
            Text(row.back).font(.system(size: secondarySize * fontScale)).foregroundStyle(.secondary).lineLimit(2)
                .accessibilityIdentifier("browser-back-\(row.id)")
            HStack(alignment: .top, spacing: 14) {
                ForEach(config.columns.filter { $0 != "noteFld" }, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(columnLabel(key)).foregroundStyle(.tertiary)
                        Text(row.metadata[key] ?? "—").foregroundStyle(.secondary)
                    }.font(.system(size: metadataSize * fontScale)).lineLimit(1)
                }
            }
        }.padding(.vertical, 4)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
        ToolbarItemGroup(placement: .topBarTrailing) {
            EditButton()
            Button { editor = EditorRequest() } label: { Image(systemName: "plus") }.accessibilityLabel("ノートを追加")
            filterMenu
            actionsMenu
        }
    }
    private var filterMenu: some View {
        Menu {
            Toggle("ノート表示", isOn: $config.notesMode).onChange(of: config.notesMode) { _, next in
                mutateOpening { config = try await model.engine.browserConfiguration(notesMode: next); selected = []; revision += 1 }
            }
            Button("表示する列") { columnPicker = true }
            Menu("並べ替え") {
                ForEach(columns.filter { config.notesMode ? $0.sortsNotes : $0.sortsCards }) { column in
                    Button(columnLabel(column.id)) { config.sortColumn = column.id; saveConfig() }
                }
                Toggle("逆順", isOn: $config.backwards).onChange(of: config.backwards) { _, _ in saveConfig() }
            }
            Menu("状態") {
                Button("すべて") { query = "" }
                Button("新規") { query = "is:new" }; Button("学習中") { query = "is:learn" }
                Button("復習") { query = "is:review" }; Button("期日到来") { query = "is:due" }
                Button("保留") { query = "is:suspended" }; Button("今日非表示") { query = "is:buried" }
                Button("マーク付き") { query = "tag:marked" }
            }
            Menu("デッキ") { ForEach(model.decks) { deck in Button(deck.name) { query = "deck:" + quoted(deck.name) } } }
            Menu("タグ") {
                Button("タグ管理") { managingTags = true }
                ForEach(tags, id: \.self) { tag in Button(tag) { query = "tag:" + quoted(tag) } }
            }
            Menu("ノートタイプ") { ForEach(types) { type in Button(type.name) { query = "mid:" + type.id } } }
            Menu("フラグ") { ForEach(0..<8, id: \.self) { value in Button(value == 0 ? "なし" : "フラグ \(value)") { query = "flag:\(value)" } } }
            Menu("保存した検索") {
                ForEach(config.savedSearches.keys.sorted(), id: \.self) { name in Button(name) { query = config.savedSearches[name] ?? "" } }
                Button("この検索を保存") { searchName = ""; saveSearchPrompt = true }.disabled(query.isEmpty)
                Button("保存した検索を管理") { manageSearches = true }
            }
            Button("取り消す") { mutate { try await model.engine.undo() } }
            Button("やり直す") { mutate { _ = try await model.engine.call("CollectionService.Redo") } }
        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.disabled(busy).accessibilityIdentifier("browser-filter-menu")
    }
    private var actionsMenu: some View {
        Menu {
            Button("すべて選択") { editMode = .active; selected = Set(ids) }.disabled(ids.isEmpty)
            Button("選択を解除") { selected = [] }
            Section {
                Button("編集") {
                    if let id = selected.first { editor = config.notesMode ? EditorRequest(noteID: id) : EditorRequest(cardID: id) }
                }.disabled(selected.count != 1)
                Button("プレビュー") { mutateOpening { preview = CardPreviewRequest(ids: try await chosenCards()) } }
                Button("保留") { performCards { try await model.engine.suspend($0) } }
                Button("保留・非表示を解除") { performCards { try await model.engine.restoreCards($0) } }
                Button("今日は表示しない") { performCards { try await model.engine.bury($0) } }
                Menu("フラグ") { ForEach(0..<8, id: \.self) { flag in Button(flag == 0 ? "なし" : "フラグ \(flag)") { performCards { try await model.engine.setFlag($0, flag: flag) } } } }
                Button("デッキを移動") { movePrompt = true }
                Button("ノートタイプを変更", action: changeType)
                Button("書き出す") { mutateOpening { selectionExport = SelectionExportRequest(cardIDs: try await chosenCards()) } }
                Button("検索と置換") { mutateOpening { findReplace = FindReplaceRequest(noteIDs: try await chosenNotes()) } }
                Button("タグを追加・削除") { tagPrompt = true }
                Button("期日を変更") { duePrompt = true }
                Button("新規カードの順番を変更") { repositionPrompt = true }
                Button("新規カードに戻す") { performCards { try await model.engine.forget($0) } }
                Button("ノートを削除", role: .destructive) { deleteConfirm = true }
            }.disabled(selected.isEmpty)
        } label: { Image(systemName: "ellipsis.circle") }.disabled(busy)
    }
    private var sheets: some View {
        list
            .sheet(item: $changingType, onDismiss: { revision += 1 }) { BackendPageView(model: model, request: $0) }
            .sheet(item: $editor, onDismiss: { revision += 1 }) { NoteEditorView(model: model, request: $0) }
            .sheet(item: $selectionExport) { SelectionExportView(model: model, request: $0) }
            .sheet(item: $findReplace, onDismiss: { revision += 1 }) { FindReplaceView(model: model, request: $0) }
            .sheet(item: $preview, onDismiss: { revision += 1 }) { CardPreviewView(model: model, request: $0) }
            .sheet(isPresented: $managingTags, onDismiss: {
                revision += 1
                Task {
                    do { tags = try await model.engine.call("TagsService.AllTags")["vals"] as? [String] ?? [] }
                    catch { self.error = error.localizedDescription }
                }
            }) { TagManagerView(model: model) }
            .sheet(isPresented: $columnPicker, onDismiss: saveConfig) { BrowserColumnPicker(columns: columns, config: $config) }
            .sheet(isPresented: $manageSearches, onDismiss: saveConfig) {
                NavigationStack {
                    List { ForEach(config.savedSearches.keys.sorted(), id: \.self) { name in
                        VStack(alignment: .leading) { Text(name); Text(config.savedSearches[name] ?? "").font(.caption).foregroundStyle(.secondary) }
                    }.onDelete { offsets in let names = config.savedSearches.keys.sorted(); for index in offsets { config.savedSearches.removeValue(forKey: names[index]) } } }
                    .navigationTitle("保存した検索").toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { manageSearches = false } } }
                }
            }
            .sheet(isPresented: $repositionPrompt) {
                NavigationStack {
                    Form {
                        Stepper("開始位置: \(position)", value: $position, in: 0...1_000_000)
                        Stepper("増分: \(positionStep)", value: $positionStep, in: 1...1000)
                        Toggle("無作為に並べる", isOn: $randomPosition); Toggle("既存カードを後ろにずらす", isOn: $shiftPosition)
                    }.navigationTitle("新規カードの順番")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { repositionPrompt = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("適用") { repositionPrompt = false; performCards { try await model.engine.reposition($0, start: position, step: positionStep, random: randomPosition, shift: shiftPosition) } } }
                    }
                }
            }
    }
    private var dialogs: some View {
        sheets
            .confirmationDialog("選択したノートとすべての関連カードを削除しますか？", isPresented: $deleteConfirm) {
                Button("削除", role: .destructive) { performNotes { try await model.engine.removeNotes($0) } }
            }
            .confirmationDialog("移動先のデッキ", isPresented: $movePrompt) {
                ForEach(model.decks) { deck in Button(deck.name) { performCards { try await model.engine.moveCards($0, deck: deck.id) } } }
            }
            .alert("タグ（空白で区切る）", isPresented: $tagPrompt) {
                TextField("タグ", text: $tagText)
                Button("追加") { performNotes { try await model.engine.tagNotes($0, tags: tagText, remove: false) } }
                Button("削除", role: .destructive) { performNotes { try await model.engine.tagNotes($0, tags: tagText, remove: true) } }
                Button("キャンセル", role: .cancel) {}
            }
            .alert("期日を変更", isPresented: $duePrompt) {
                TextField("今日からの日数（例: 3、3-7）", text: $days)
                Button("変更") { performCards { try await model.engine.setDue($0, days: days) } }; Button("キャンセル", role: .cancel) {}
            }
            .alert("検索を保存", isPresented: $saveSearchPrompt) {
                TextField("名前", text: $searchName)
                Button("保存") { config.savedSearches[searchName] = query; saveConfig() }.disabled(searchName.isEmpty)
                Button("キャンセル", role: .cancel) {}
            }
            .alert("処理できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func initialize() async {
        do {
            config = try await model.engine.browserConfiguration()
            columns = try await model.engine.browserColumns()
            tags = try await model.engine.call("TagsService.AllTags")["vals"] as? [String] ?? []
            types = try await model.engine.noteTypes()
            if query.isEmpty {
                let defaultQuery = try await model.engine.call("ConfigService.GetConfigString", ["key": "DEFAULT_SEARCH_TEXT"])["val"] as? String ?? ""
                let restore = try await model.engine.call("ConfigService.GetConfigBool", ["key": "RESTORE_POSITION_BROWSER"])["val"] as? Bool ?? false
                query = !defaultQuery.isEmpty ? defaultQuery : restore ? UserDefaults.standard.string(forKey: model.profilePreferenceKey("lastBrowserSearch")) ?? "" : ""
            }
            loaded = true
        } catch { self.error = error.localizedDescription }
    }
    private func search() async {
        guard loaded else { return }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            busy = true
            defer { busy = false }
            let result = try await model.engine.searchBrowserIDs(query, config: config)
            try Task.checkCancellation()
            let cards = try await model.engine.browserRows(Array(result.prefix(100)), config: config, showMediaFilenames: showMediaFilenames)
            try Task.checkCancellation()
            ids = result; rows = cards; selected.formIntersection(Set(ids)); completedQuery = query
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func edit(_ row: BrowserCard) { editor = config.notesMode ? EditorRequest(noteID: row.noteID, deckID: row.deckID) : EditorRequest(cardID: row.id, deckID: row.deckID) }
    private func columnLabel(_ key: String) -> String { columns.first(where: { $0.id == key }).map { config.notesMode ? $0.noteLabel : $0.cardLabel } ?? key }
    private func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    private func flagColor(_ flag: Int) -> Color { [.gray, .red, .orange, .green, .blue, .pink, .cyan, .purple][min(7, max(0, flag))] }
    private func saveConfig() { mutateOpening { try await model.engine.saveBrowserConfiguration(config); revision += 1 } }
    private func chosenCards() async throws -> [String] { let ordered = ids.filter { selected.contains($0) }; return config.notesMode ? try await model.engine.cardIDsForNotes(ordered) : ordered }
    private func chosenNotes() async throws -> [String] { let ordered = ids.filter { selected.contains($0) }; return config.notesMode ? ordered : try await model.engine.noteIDsForCards(ordered) }
    private func changeType() {
        mutateOpening {
            let notes = try await chosenNotes()
            let response = try await model.engine.call("NotesService.GetSingleNotetypeOfNotes", ["noteIds": notes])
            guard let old = response["ntid"] as? String else { throw EngineError(message: "同じノートタイプのノートを選んでください。") }
            changingType = BackendPageRequest(path: "change-notetype/" + old, title: "ノートタイプを変更", noteIDs: notes)
        }
    }
    private func performCards(_ action: @escaping ([String]) async throws -> Void) { mutate { let cards = try await chosenCards(); try await action(cards) } }
    private func performNotes(_ action: @escaping ([String]) async throws -> Void) { mutate { let notes = try await chosenNotes(); try await action(notes) } }
    private func loadMore() { mutateOpening { rows += try await model.engine.browserRows(Array(ids.dropFirst(rows.count).prefix(100)), config: config, showMediaFilenames: showMediaFilenames) } }
    private func mutateOpening(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { try await action() } catch { self.error = error.localizedDescription } }
    }
    private func mutate(_ action: @escaping () async throws -> Void) {
        mutateOpening { try await action(); selected = []; revision += 1; model.refreshAfterEditing() }
    }
}

struct BrowserColumnPicker: View {
    let columns: [BrowserColumn]
    @Binding var config: BrowserConfiguration
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("表示する列") {
                    ForEach(config.columns, id: \.self) { key in Text(label(key)) }
                        .onMove { config.columns.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in var result = config.columns; result.remove(atOffsets: offsets); if !result.isEmpty { config.columns = result } }
                }
                Section("追加できる列") {
                    ForEach(columns.filter { !config.columns.contains($0.id) }) { column in Button(label(column.id)) { config.columns.append(column.id) } }
                }
            }.navigationTitle("ブラウザーの列")
            .toolbar { ToolbarItem(placement: .cancellationAction) { EditButton() }; ToolbarItem(placement: .confirmationAction) { Button("保存") { dismiss() } } }
        }
    }
    private func label(_ key: String) -> String { columns.first(where: { $0.id == key }).map { config.notesMode ? $0.noteLabel : $0.cardLabel } ?? key }
}
