import SwiftUI

struct BrowserView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isTruncated") private var truncateRows = false
    @AppStorage("relativeCardBrowserFontSize") private var fontPercent = 100
    @AppStorage("card_browser_show_media_filenames") private var showMediaFilenames = false
    @ScaledMetric(relativeTo: .body) private var primarySize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var secondarySize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var metadataSize: CGFloat = 11
    private var fontScale: CGFloat { CGFloat(max(10, min(200, fontPercent))) / 100 }
    @State private var query: String
    private let hasExplicitInitialSearch: Bool
    @State private var openingProfileID: String
    @State private var positionPreferenceKey: String
    @State private var config = BrowserConfiguration(notesMode: false, columns: ["noteFld", "template", "cardDue", "deck"], sortColumn: "noteFld", backwards: false, savedSearches: [:])
    @State private var columns: [BrowserColumn] = []
    @State private var tags: [String] = []
    @State private var types: [NamedID] = []
    @State private var loaded = false
    @State private var completedQuery = ""
    @State private var ids: [String] = []
    @State private var rows: [BrowserCard] = []
    @State private var selected: Set<String> = []
    @State private var selectionOrder: [String] = []
    @State private var editMode = EditMode.inactive
    @State private var editor: EditorRequest?
    @State private var changingType: BackendPageRequest?
    @State private var preview: CardPreviewRequest?
    @State private var filteredDeck: FilteredDeckRequest?
    @State private var forgettingCards: BrowserForgetRequest?
    @State private var findReplace: FindReplaceRequest?
    @State private var selectionExport: SelectionExportRequest?
    @State private var busy = false
    @State private var searchInFlight: UUID?
    private var interactionBlocked: Bool { busy || searchInFlight != nil }
    @State private var error: String?
    @State private var deleteConfirm = false
    @State private var tagPrompt = false
    @State private var tagText = ""
    @State private var duePrompt = false
    @State private var days = ""
    @State private var movePrompt = false
    @State private var browserOptions = false
    @State private var searchFilters = false
    @State private var fieldSearch = false
    @State private var searchHistory: [BrowserSearchRequest] = []
    @State private var activeSearchRequest: BrowserSearchRequest?
    @State private var historyRequest: BrowserSearchHistoryRequest?
    @State private var columnPicker = false
    @State private var saveSearchPrompt = false
    @State private var searchName = ""
    @State private var savedSearchValue = ""
    @State private var manageSearches = false
    @State private var managingTags = false
    @State private var repositionPrompt = false
    @State private var position = 1
    @State private var positionStep = 1
    @State private var randomPosition = false
    @State private var shiftPosition = true
    @State private var revision = 0
    init(model: StudyModel, initialSearch: String? = nil) {
        self.model = model
        hasExplicitInitialSearch = initialSearch != nil
        _openingProfileID = State(initialValue: model.currentProfile.id)
        _positionPreferenceKey = State(initialValue: model.profilePreferenceKey("lastBrowserSearch"))
        _query = State(initialValue: initialSearch ?? model.browserSearch)
    }
    private struct SearchTaskIdentity: Hashable {
        let loaded: Bool
        let request: BrowserSearchRequest
        let revision: Int
        let notesMode: Bool
        let showMediaFilenames: Bool
    }
    private var searchTaskIdentity: SearchTaskIdentity {
        SearchTaskIdentity(loaded: loaded, request: effectiveSearchRequest, revision: revision,
                           notesMode: config.notesMode, showMediaFilenames: showMediaFilenames)
    }
    var body: some View {
        NavigationStack { dialogs }
            .task {
                traceSelection("initialize.start")
                await initialize()
                traceSelection("initialize.end")
            }
            .onAppear { traceSelection("appear") }
            .onChange(of: editMode.isEditing) { _, _ in traceSelection("editing.changed") }
            .onDisappear { savePosition() }
            .task(id: searchTaskIdentity) { await search() }
    }
    private var list: some View {
        List(selection: Binding(get: { selected }, set: { next in
            traceSelection("binding.set", incoming: next.count)
            updateSelection(next)
        })) {
            if effectiveSearchRequest.hasFilters { activeFilterSummary }
            Section {
                ForEach(rows) { row in
                    Group {
                        if editMode.isEditing { rowView(row) }
                        else { Button { edit(row) } label: { rowView(row) }.accessibilityIdentifier("browser-card-\(row.id)") }
                    }
                    .tag(row.id)
                    .contextMenu {
                        Button(AppText.localized("編集")) { edit(row) }
                        Button(AppText.localized("プレビュー")) { openPreview(selected: [row.id]) }.disabled(row.cardIDs.isEmpty)
                        Button(row.suspended ? AppText.localized("保留を解除") : AppText.localized("保留")) { mutate { if row.suspended { try await model.engine.restoreCards(row.cardIDs) } else { try await model.engine.suspend(row.cardIDs) } } }
                        Button(AppText.localized("今日は表示しない")) { mutate { try await model.engine.bury(row.cardIDs) } }
                    }
                }
                if rows.count < ids.count { Button(AppText.localized("さらに表示（\(rows.count) / \(ids.count)）"), action: loadMore).disabled(interactionBlocked) }
            } header: {
                Text(config.notesMode
                     ? AppText.localized("\(ids.count)ノート · \(selected.count)件選択中")
                     : AppText.localized("\(ids.count)枚 · \(selected.count)件選択中"))
                    .accessibilityIdentifier("browser-results").accessibilityValue(completedQuery)
            }
            if interactionBlocked { ProgressView() }
        }
        .environment(\.editMode, $editMode)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: AppText.localized("検索（deck:、tag:、is:due など）"))
        .onSubmit(of: .search) { rememberSearch() }
        .studyThemeSurface()
        .navigationTitle(config.notesMode ? AppText.localized("ノートブラウザー") : AppText.localized("カードブラウザー"))
        .toolbar { toolbar }
    }
    private func filterChip<Value>(_ title: String, names: [String], key: WritableKeyPath<BrowserSearchRequest, [Value]>, id: String) -> some View {
        Button { updateFilter(key, values: []) } label: {
            Label(title + ": " + names.joined(separator: ", "), systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered).disabled(interactionBlocked)
        .accessibilityIdentifier("browser-filter-chip-" + id)
        .accessibilityHint(AppText.localized("この絞り込みを解除"))
    }
    private var activeFilterSummary: some View {
        ScrollView(.horizontal) {
            HStack {
                if !effectiveSearchRequest.deckIDs.isEmpty {
                    filterChip(AppText.localized("デッキ"), names: effectiveSearchRequest.deckIDs.map { id in model.decks.first(where: { $0.id == id })?.name ?? id }, key: \.deckIDs, id: "decks")
                }
                if !effectiveSearchRequest.flags.isEmpty {
                    filterChip(AppText.localized("フラグ"), names: effectiveSearchRequest.flags.map { model.flagLabels.name($0.rawValue) }, key: \.flags, id: "flags")
                }
                if !effectiveSearchRequest.tags.isEmpty {
                    filterChip(AppText.localized("タグ"), names: effectiveSearchRequest.tags, key: \.tags, id: "tags")
                }
                if !effectiveSearchRequest.noteTypeIDs.isEmpty {
                    filterChip(AppText.localized("ノートタイプ"), names: effectiveSearchRequest.noteTypeIDs.map { id in types.first(where: { $0.id == id })?.name ?? id }, key: \.noteTypeIDs, id: "types")
                }
                if !effectiveSearchRequest.cardStates.isEmpty {
                    filterChip(AppText.localized("状態"), names: effectiveSearchRequest.cardStates.map { state in
                        switch state {
                        case .new: return AppText.localized("新規")
                        case .learning: return AppText.localized("学習中")
                        case .review: return AppText.localized("復習")
                        case .buried: return AppText.localized("今日非表示")
                        case .suspended: return AppText.localized("保留")
                        }
                    }, key: \.cardStates, id: "states")
                }
            }
        }.accessibilityIdentifier("browser-active-filters")
    }
    @ViewBuilder private func rowView(_ row: BrowserCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if row.suspended { Image(systemName: "pause.circle").foregroundStyle(.orange) }
                if row.flag > 0 { Image(systemName: "flag.fill").foregroundStyle(flagColor(row.flag)) }
                Text(row.front.isEmpty ? AppText.localized("（空のフィールド）") : row.front).font(.system(size: primarySize * fontScale)).lineLimit(truncateRows ? 3 : nil).foregroundStyle(.primary)
                    .accessibilityIdentifier("browser-front-\(row.id)")
            }
            Text(row.back).font(.system(size: secondarySize * fontScale)).foregroundStyle(.secondary).lineLimit(truncateRows ? 3 : nil)
                .accessibilityIdentifier("browser-back-\(row.id)")
            HStack(alignment: .top, spacing: 14) {
                ForEach(config.columns.filter { $0 != "noteFld" }, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(columnLabel(key)).foregroundStyle(.tertiary)
                        Text(row.metadata[key] ?? "—").foregroundStyle(.secondary)
                    }.font(.system(size: metadataSize * fontScale)).lineLimit(truncateRows ? 3 : nil)
                }
            }
        }.padding(.vertical, 4)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("閉じる")) { dismiss() } }
        ToolbarItemGroup(placement: .topBarTrailing) {
            EditButton().environment(\.editMode, $editMode).accessibilityIdentifier("browser-edit-mode")
            Button { editor = EditorRequest() } label: { Image(systemName: "plus") }.accessibilityLabel(AppText.localized("ノートを追加"))
            filterMenu
            actionsMenu
        }
    }
    private var filterMenu: some View {
        Menu {
            Button(AppText.localized("ブラウザーの設定")) { browserOptions = true }.accessibilityIdentifier("browser-options-open")
            Toggle(AppText.localized("ノート表示"), isOn: $config.notesMode).onChange(of: config.notesMode) { _, next in
                mutateOpening { config = try await model.engine.browserConfiguration(notesMode: next); updateSelection([]); revision += 1 }
            }
            Button(AppText.localized("表示する列")) { columnPicker = true }
            Menu(AppText.localized("並べ替え")) {
                ForEach(columns.filter { config.notesMode ? $0.sortsNotes : $0.sortsCards }) { column in
                    Button(columnLabel(column.id)) { config.sortColumn = column.id; saveConfig() }
                }
                Toggle(AppText.localized("逆順"), isOn: $config.backwards).onChange(of: config.backwards) { _, _ in saveConfig() }
            }
            Button(AppText.localized("最近の検索")) {
                let key = model.profilePreferenceKey("browserSearchHistory")
                do {
                    searchHistory = try BrowserSearchHistory.entries(key: key)
                    historyRequest = BrowserSearchHistoryRequest(preferenceKey: key, profileID: model.currentProfile.id, engine: model.engine)
                } catch { self.error = AppText.localized("検索履歴を読み込めませんでした。") }
            }.accessibilityIdentifier("browser-history-open")
            Button(AppText.localized("検索条件を編集")) { searchFilters = true }.accessibilityIdentifier("browser-search-filters")
            Button(AppText.localized("フィールドを検索")) { fieldSearch = true }.accessibilityIdentifier("browser-field-search")
            Menu(AppText.localized("状態")) {
                Button(AppText.localized("すべて")) { updateFilter(\.cardStates, values: []) }
                Button(AppText.localized("新規")) { updateFilter(\.cardStates, values: [.new]) }; Button(AppText.localized("学習中")) { updateFilter(\.cardStates, values: [.learning]) }
                Button(AppText.localized("復習")) { updateFilter(\.cardStates, values: [.review]) }; Button(AppText.localized("期日到来")) { submitSearch("is:due") }
                Button(AppText.localized("保留")) { updateFilter(\.cardStates, values: [.suspended]) }; Button(AppText.localized("今日非表示")) { updateFilter(\.cardStates, values: [.buried]) }
                Button(AppText.localized("マーク付き")) { updateFilter(\.tags, values: ["marked"]) }
            }
            Menu(AppText.localized("デッキ")) { ForEach(model.decks) { deck in Button(deck.name) { updateFilter(\.deckIDs, values: [deck.id]) } } }
            Menu(AppText.localized("タグ")) {
                Button(AppText.localized("タグ管理")) { managingTags = true }
                ForEach(tags, id: \.self) { tag in Button(tag) { updateFilter(\.tags, values: [tag]) } }
            }
            Menu(AppText.localized("ノートタイプ")) { ForEach(types) { type in Button(type.name) { updateFilter(\.noteTypeIDs, values: [type.id]) } } }
            Menu(AppText.localized("フラグ")) { ForEach(0..<8, id: \.self) { value in Button(model.flagLabels.name(value)) { updateFilter(\.flags, values: [BrowserSearchFlag(rawValue: value)!]) }.accessibilityIdentifier("browser-filter-flag-\(value)") } }.accessibilityIdentifier("browser-filter-flags")
            Menu(AppText.localized("保存した検索")) {
                ForEach(config.savedSearches.keys.sorted(), id: \.self) { name in Button(name) { submitSearch(config.savedSearches[name] ?? "") } }
                Button(AppText.localized("この検索を保存")) {
                    withResolvedSearch { value in searchName = ""; savedSearchValue = value; saveSearchPrompt = true }
                }.disabled(effectiveSearchRequest.isEmpty)
                Button(AppText.localized("保存した検索を管理")) { manageSearches = true }
            }
            Button(AppText.localized("フィルターデッキを作成")) {
                withResolvedSearch { filteredDeck = FilteredDeckRequest(initialSearch: $0) }
            }.accessibilityIdentifier("browser-create-filtered")
            Button(AppText.localized("検索と置換")) { findReplace = FindReplaceRequest(noteIDs: []) }
                .accessibilityIdentifier("browser-find-replace")
            Button(AppText.localized("取り消す")) { mutate { try await model.engine.undo() } }
            Button(AppText.localized("やり直す")) { mutate { _ = try await model.engine.call("CollectionService.Redo") } }
        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.disabled(interactionBlocked).accessibilityIdentifier("browser-filter-menu")
    }
    private var actionsMenu: some View {
        Menu {
            Button(AppText.localized("すべて選択")) {
                traceSelection("all.enter")
                editMode = .active
                traceSelection("all.editing")
                updateSelection(Set(ids))
                traceSelection("all.exit")
            }.disabled(ids.isEmpty)
            Button(AppText.localized("選択を解除")) { updateSelection([]) }
            Button(AppText.localized("プレビュー")) { openPreview(selected: selectionOrder) }.disabled(ids.isEmpty)
            Section {
                Button(AppText.localized("編集")) {
                    if let id = selected.first { editor = config.notesMode ? EditorRequest(noteID: id) : EditorRequest(cardID: id) }
                }.disabled(selected.count != 1)
                Button(AppText.localized("保留")) { performCards { try await model.engine.suspend($0) } }
                Button(AppText.localized("保留・非表示を解除")) { performCards { try await model.engine.restoreCards($0) } }
                Button(AppText.localized("今日は表示しない")) { performCards { try await model.engine.bury($0) } }
                Menu(AppText.localized("フラグ")) { ForEach(0..<8, id: \.self) { flag in Button(model.flagLabels.name(flag)) { performCards { try await model.engine.setFlag($0, flag: flag) } } } }
                Button(AppText.localized("デッキを移動")) { movePrompt = true }
                Button(AppText.localized("ノートタイプを変更"), action: changeType)
                Button(AppText.localized("書き出す")) { mutateOpening { selectionExport = SelectionExportRequest(cardIDs: try await chosenCards()) } }
                Button(AppText.localized("検索と置換")) { mutateOpening { findReplace = FindReplaceRequest(noteIDs: try await chosenNotes()) } }
                Button(AppText.localized("タグを追加・削除")) { tagPrompt = true }
                Button(AppText.localized("期日を変更")) { duePrompt = true }
                Button(AppText.localized("新規カードの順番を変更")) { repositionPrompt = true }
                Button(AppText.localized("新規カードに戻す")) { openForgetCards() }.accessibilityIdentifier("browser-forget-open")
                Button(AppText.localized("ノートを削除"), role: .destructive) { deleteConfirm = true }
            }.disabled(selected.isEmpty)
        } label: { Image(systemName: "ellipsis.circle") }.disabled(interactionBlocked).accessibilityIdentifier("browser-actions-menu")
    }
    private var sheets: some View {
        list
            .sheet(item: $changingType, onDismiss: { revision += 1 }) { BackendPageView(model: model, request: $0) }
            .sheet(item: $editor, onDismiss: { revision += 1 }) { NoteEditorView(model: model, request: $0) }
            .sheet(item: $selectionExport) { SelectionExportView(model: model, request: $0) }
            .sheet(item: $forgettingCards) { request in
                BrowserForgetCardsView(model: model, request: request) { updateSelection([]); revision += 1 }
            }
            .sheet(item: $filteredDeck, onDismiss: { revision += 1 }) { FilteredDeckView(model: model, request: $0) }
            .sheet(item: $findReplace, onDismiss: { revision += 1 }) { FindReplaceView(model: model, request: $0) }
            .sheet(item: $preview, onDismiss: { revision += 1 }) { CardPreviewView(model: model, request: $0) }
            .sheet(isPresented: $managingTags, onDismiss: {
                revision += 1
                Task {
                    do { tags = try await model.engine.call("TagsService.AllTags")["vals"] as? [String] ?? [] }
                    catch { self.error = error.localizedDescription }
                }
            }) { TagManagerView(model: model) }
            .sheet(item: $historyRequest) { request in
                BrowserSearchHistoryView(entries: $searchHistory, preferenceKey: request.preferenceKey, resolve: { entry in
                    try await request.engine.browserSearchQuery(entry)
                }) { entry, _ in
                    guard model.currentProfile.id == request.profileID else {
                        throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
                    }
                    try commitSearch(entry)
                }
            }
            .sheet(isPresented: $searchFilters) {
                BrowserSearchFiltersView(model: model, request: effectiveSearchRequest, tags: tags, noteTypes: types) { entry, _ in
                    try commitSearch(entry)
                }
            }
            .sheet(isPresented: $fieldSearch) { BrowserFieldSearchView(model: model, currentRequest: effectiveSearchRequest) { entry, _ in try commitSearch(entry) } }
            .sheet(isPresented: $browserOptions, onDismiss: {
                mutateOpening {
                    let saved = try await model.engine.browserConfiguration()
                    if saved.notesMode != config.notesMode { updateSelection([]) }
                    config = saved; revision += 1
                }
            }) { BrowserOptionsView(model: model) }
            .sheet(isPresented: $columnPicker, onDismiss: saveConfig) { BrowserColumnPicker(columns: columns, config: $config) }
            .sheet(isPresented: $manageSearches, onDismiss: saveConfig) {
                NavigationStack {
                    List { ForEach(config.savedSearches.keys.sorted(), id: \.self) { name in
                        VStack(alignment: .leading) { Text(name); Text(config.savedSearches[name] ?? "").font(.caption).foregroundStyle(.secondary) }
                    }.onDelete { offsets in let names = config.savedSearches.keys.sorted(); for index in offsets { config.savedSearches.removeValue(forKey: names[index]) } } }
                    .studyThemeSurface().navigationTitle(AppText.localized("保存した検索")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("閉じる")) { manageSearches = false } } }
                }
            }
            .sheet(isPresented: $repositionPrompt) {
                NavigationStack {
                    Form {
                        Stepper(AppText.localized("開始位置: \(position)"), value: $position, in: 0...1_000_000)
                        Stepper(AppText.localized("増分: \(positionStep)"), value: $positionStep, in: 1...1000)
                        Toggle(AppText.localized("無作為に並べる"), isOn: $randomPosition); Toggle(AppText.localized("既存カードを後ろにずらす"), isOn: $shiftPosition)
                    }.studyThemeSurface().navigationTitle(AppText.localized("新規カードの順番"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル")) { repositionPrompt = false } }
                        ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("適用")) { repositionPrompt = false; performCards { try await model.engine.reposition($0, start: position, step: positionStep, random: randomPosition, shift: shiftPosition) } } }
                    }
                }
            }
    }
    private var dialogs: some View {
        sheets
            .confirmationDialog(AppText.localized("選択したノートとすべての関連カードを削除しますか？"), isPresented: $deleteConfirm) {
                Button(AppText.localized("削除"), role: .destructive) { performNotes { try await model.engine.removeNotes($0) } }
            }
            .confirmationDialog(AppText.localized("移動先のデッキ"), isPresented: $movePrompt) {
                ForEach(model.decks) { deck in Button(deck.name) { performCards { try await model.engine.moveCards($0, deck: deck.id) } } }
            }
            .alert(AppText.localized("タグ（空白で区切る）"), isPresented: $tagPrompt) {
                TextField(AppText.localized("タグ"), text: $tagText)
                Button(AppText.localized("追加")) { performNotes { try await model.engine.tagNotes($0, tags: tagText, remove: false) } }
                Button(AppText.localized("削除"), role: .destructive) { performNotes { try await model.engine.tagNotes($0, tags: tagText, remove: true) } }
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
            .alert(AppText.localized("期日を変更"), isPresented: $duePrompt) {
                TextField(AppText.localized("今日からの日数（例: 3、3-7）"), text: $days)
                Button(AppText.localized("変更")) { performCards { try await model.engine.setDue($0, days: days) } }; Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
            .alert(AppText.localized("検索を保存"), isPresented: $saveSearchPrompt) {
                TextField(AppText.localized("名前"), text: $searchName)
                Button(AppText.localized("保存")) { config.savedSearches[searchName] = savedSearchValue; saveConfig() }.disabled(searchName.isEmpty)
                Button(AppText.localized("キャンセル"), role: .cancel) {}
            }
            .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func initialize() async {
        do {
            config = try await model.engine.browserConfiguration()
            columns = try await model.engine.browserColumns()
            tags = try await model.engine.call("TagsService.AllTags")["vals"] as? [String] ?? []
            types = try await model.engine.noteTypes()
            if query.isEmpty && !hasExplicitInitialSearch {
                let defaultQuery = try await model.engine.call("ConfigService.GetConfigString", ["key": "DEFAULT_SEARCH_TEXT"])["val"] as? String ?? ""
                let request = BrowserSearchPosition.initialRequest(query: query, explicit: hasExplicitInitialSearch,
                    defaultQuery: defaultQuery)
                guard model.currentProfile.id == openingProfileID else {
                    throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
                }
                activeSearchRequest = request; query = request.query
            }
            guard model.currentProfile.id == openingProfileID else {
                throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
            }
            loaded = true
            do { searchHistory = try BrowserSearchHistory.entries(key: model.profilePreferenceKey("browserSearchHistory")) }
            catch { self.error = AppText.localized("検索履歴を読み込めませんでした。") }
        } catch { self.error = error.localizedDescription }
    }
    private func savePosition() {
        guard loaded, model.currentProfile.id == openingProfileID else { return }
        do { try BrowserSearchPosition.save(effectiveSearchRequest, key: positionPreferenceKey) }
        catch { NSLog("browser.search.position.save.failed") }
    }
    private var effectiveSearchRequest: BrowserSearchRequest {
        var request = activeSearchRequest ?? BrowserSearchRequest()
        request.query = query
        return request
    }
    private func commitSearch(_ request: BrowserSearchRequest) throws {
        guard model.currentProfile.id == openingProfileID else {
            throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
        }
        let updated = try BrowserSearchHistory.remember(request, key: model.profilePreferenceKey("browserSearchHistory"))
        searchHistory = updated; activeSearchRequest = request; query = request.query
    }
    private func rememberSearch() {
        do { try commitSearch(effectiveSearchRequest) }
        catch { self.error = AppText.localized("検索履歴を保存できませんでした。") }
    }
    private func submitSearch(_ value: String) {
        var request = effectiveSearchRequest
        request.query = value
        submitRequest(request)
    }
    private func updateFilter<Value>(_ key: WritableKeyPath<BrowserSearchRequest, [Value]>, values: [Value]) {
        var request = effectiveSearchRequest
        request[keyPath: key] = values
        submitRequest(request)
    }
    private func submitRequest(_ request: BrowserSearchRequest) {
        let engine = model.engine, profileID = model.currentProfile.id
        mutateOpening {
            if request.hasFilters { _ = try await engine.browserSearchQuery(request) }
            guard model.currentProfile.id == profileID else {
                throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
            }
            try commitSearch(request)
        }
    }
    private func withResolvedSearch(_ action: @escaping (String) -> Void) {
        let request = effectiveSearchRequest, engine = model.engine, profileID = model.currentProfile.id
        mutateOpening {
            let value = request.hasFilters ? try await engine.browserSearchQuery(request) : request.query
            guard model.currentProfile.id == profileID, profileID == openingProfileID else {
                throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
            }
            action(value)
        }
    }
    private func search() async {
        guard loaded, model.currentProfile.id == openingProfileID else { return }
        let identity = searchTaskIdentity
        let request = identity.request, snapshot = config, filenames = showMediaFilenames
        let engine = model.engine, profileID = openingProfileID
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            try Task.checkCancellation()
            let token = UUID()
            searchInFlight = token
            defer { if searchInFlight == token { searchInFlight = nil } }
            let resolved = request.hasFilters ? try await engine.browserSearchQuery(request) : request.query
            try Task.checkCancellation()
            let result = try await engine.searchBrowserIDs(resolved, config: snapshot)
            try Task.checkCancellation()
            let cards = try await engine.browserRows(Array(result.prefix(100)), config: snapshot, showMediaFilenames: filenames)
            try Task.checkCancellation()
            guard model.currentProfile.id == profileID, searchTaskIdentity == identity else { return }
            ids = result; rows = cards; updateSelection(selected.intersection(Set(ids))); completedQuery = resolved
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func edit(_ row: BrowserCard) { editor = config.notesMode ? EditorRequest(noteID: row.noteID, deckID: row.deckID) : EditorRequest(cardID: row.id, deckID: row.deckID) }
    private func columnLabel(_ key: String) -> String { columns.first(where: { $0.id == key }).map { config.notesMode ? $0.noteLabel : $0.cardLabel } ?? key }
    private func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    private func flagColor(_ flag: Int) -> Color { [.gray, .red, .orange, .green, .blue, .pink, .cyan, .purple][min(7, max(0, flag))] }
    private func saveConfig() { mutateOpening { try await model.engine.saveBrowserConfiguration(config); revision += 1 } }
    private func traceSelection(_ phase: String, incoming: Int = -1) {
        #if DEBUG
        guard UITestIsolation.namespace() != nil else { return }
        NSLog("browser.selection.trace phase=%@ rows=%d selected=%d ordered=%d incoming=%d editing=%d busy=%d notes=%d",
              phase, ids.count, selected.count, selectionOrder.count, incoming,
              editMode.isEditing ? 1 : 0, busy ? 1 : 0, config.notesMode ? 1 : 0)
        #endif
    }
    private func updateSelection(_ next: Set<String>) {
        traceSelection("update.enter", incoming: next.count)
        // AnkiDroid's LinkedHashSet preserves the order rows were selected.
        selectionOrder = BrowserSelectionOrder.updating(previous: selectionOrder, next: next, rowIDs: ids)
        selected = next
        traceSelection("update.exit", incoming: next.count)
    }
    private func openPreview(selected: [String]) {
        // Use the complete ordered result, not just the first displayed page.
        let rowIDs = ids
        let notesMode = config.notesMode
        mutateOpening {
            preview = try await model.engine.browserPreview(rowIDs: rowIDs, selected: selected, notesMode: notesMode)
        }
    }
    private func chosenCards() async throws -> [String] { let ordered = ids.filter { selected.contains($0) }; return config.notesMode ? try await model.engine.cardIDsForNotes(ordered) : ordered }
    private func chosenNotes() async throws -> [String] { let ordered = ids.filter { selected.contains($0) }; return config.notesMode ? ordered : try await model.engine.noteIDsForCards(ordered) }
    private func openForgetCards() {
        let profileID = model.currentProfile.id, engine = model.engine
        let ordered = ids.filter { selected.contains($0) }, notesMode = config.notesMode
        mutateOpening {
            guard profileID == openingProfileID else {
                throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
            }
            let cards = notesMode ? try await engine.cardIDsForNotes(ordered) : ordered
            guard model.currentProfile.id == profileID else {
                throw EngineError(message: AppText.localized("プロファイルが変わりました。検索画面を開き直してください。"))
            }
            guard !cards.isEmpty else { return }
            forgettingCards = BrowserForgetRequest(cardIDs: cards, profileID: profileID)
        }
    }
    private func changeType() {
        mutateOpening {
            let notes = try await chosenNotes()
            let response = try await model.engine.call("NotesService.GetSingleNotetypeOfNotes", ["noteIds": notes])
            guard let old = response["ntid"] as? String else { throw EngineError(message: AppText.localized("同じノートタイプのノートを選んでください。")) }
            changingType = BackendPageRequest(path: "change-notetype/" + old, title: AppText.localized("ノートタイプを変更"), noteIDs: notes)
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
        mutateOpening { try await action(); updateSelection([]); revision += 1; model.refreshAfterEditing() }
    }
}

struct BrowserColumnPicker: View {
    let columns: [BrowserColumn]
    @Binding var config: BrowserConfiguration
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section(AppText.localized("表示する列")) {
                    ForEach(config.columns, id: \.self) { key in Text(label(key)) }
                        .onMove { config.columns.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in var result = config.columns; result.remove(atOffsets: offsets); if !result.isEmpty { config.columns = result } }
                }
                Section(AppText.localized("追加できる列")) {
                    ForEach(columns.filter { !config.columns.contains($0.id) }) { column in Button(label(column.id)) { config.columns.append(column.id) } }
                }
            }.studyThemeSurface().navigationTitle(AppText.localized("ブラウザーの列"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { EditButton() }; ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("保存")) { dismiss() } } }
        }
    }
    private func label(_ key: String) -> String { columns.first(where: { $0.id == key }).map { config.notesMode ? $0.noteLabel : $0.cardLabel } ?? key }
}
