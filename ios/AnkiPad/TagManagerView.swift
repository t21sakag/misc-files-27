import SwiftUI

private struct TagEditRequest: Identifiable {
    let id = UUID()
    let tag: String
    let moving: Bool
}
private struct TagTreeEntry: Identifiable {
    var id: String { name }
    let name: String
    let label: String
    let depth: Int
    let hasChildren: Bool
    let collapsed: Bool
    static func flatten(_ root: [String: Any]) -> [Self] {
        var entries: [Self] = []
        func visit(_ node: [String: Any], parent: String, depth: Int) {
            let label = node["name"] as? String ?? ""
            let children = node["children"] as? [[String: Any]] ?? []
            let name = label.isEmpty ? parent : parent.isEmpty ? label : parent + "::" + label
            if !label.isEmpty {
                entries.append(Self(name: name, label: label, depth: depth, hasChildren: !children.isEmpty, collapsed: node["collapsed"] as? Bool ?? false))
            }
            for child in children { visit(child, parent: name, depth: label.isEmpty ? depth : depth + 1) }
        }
        visit(root, parent: "", depth: 0)
        return entries
    }
}
struct TagManagerView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var tree: [TagTreeEntry] = []
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?
    @State private var editing: TagEditRequest?
    @State private var removing: String?
    private var visibleTags: [TagTreeEntry] {
        if !search.isEmpty { return tree.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        var hiddenBelow: Int?
        var visible: [TagTreeEntry] = []
        for entry in tree {
            if let depth = hiddenBelow {
                if entry.depth > depth { continue }
                hiddenBelow = nil
            }
            visible.append(entry)
            if entry.hasChildren && entry.collapsed { hiddenBelow = entry.depth }
        }
        return visible
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleTags) { entry in
                    HStack {
                        if entry.hasChildren {
                            Button { setCollapsed(entry) } label: {
                                Image(systemName: entry.collapsed && search.isEmpty ? "chevron.right" : "chevron.down")
                            }.buttonStyle(.borderless).accessibilityLabel(entry.name + (entry.collapsed ? "を展開" : "を折りたたむ"))
                                .accessibilityIdentifier("tag-collapse-" + entry.name)
                                .accessibilityValue(entry.collapsed ? "折りたたみ" : "展開")
                                .disabled(!search.isEmpty)
                        }
                        Text(search.isEmpty ? entry.label : entry.name).accessibilityIdentifier("tag-name-" + entry.name)
                        Spacer()
                        Menu {
                            Button("名前を変更") { editing = TagEditRequest(tag: entry.name, moving: false) }
                            Button("別の親タグへ移動") { editing = TagEditRequest(tag: entry.name, moving: true) }
                            Button("タグを削除", role: .destructive) { removing = entry.name }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel(entry.name + "の操作").accessibilityIdentifier("tag-actions-" + entry.name)
                    }.padding(.leading, search.isEmpty ? CGFloat(entry.depth) * 14 : 0)
                }
                if tree.isEmpty && !busy { Text("タグがありません").foregroundStyle(.secondary) }
                if busy { ProgressView() }
            }
            .disabled(busy)
            .searchable(text: $search, prompt: "タグを検索")
            .studyThemeSurface().navigationTitle("タグ管理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .primaryAction) {
                    Menu("管理", systemImage: "tag") {
                        Button("未使用タグを整理") { run("TagsService.ClearUnusedTags") }
                        Button("取り消す") { run("CollectionService.Undo", backup: false) }
                        Button("やり直す") { run("CollectionService.Redo", backup: false) }
                    }.disabled(busy)
                }
            }
            .task { busy = true; await reload(); busy = false }
            .sheet(item: $editing) { request in
                TagEditForm(request: request) { value in
                    let engine = model.engine
                    try await engine.backup()
                    if request.moving {
                        _ = try await engine.call("TagsService.ReparentTags", ["tags": [request.tag], "newParent": value])
                    } else {
                        _ = try await engine.call("TagsService.RenameTags", ["currentPrefix": request.tag, "newPrefix": value])
                    }
                    await reload()
                    model.refreshAfterEditing()
                }
            }
            .confirmationDialog("タグを削除しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                if let tag = removing { Button("タグと子タグを削除", role: .destructive) { run("TagsService.RemoveTags", ["val": tag]); removing = nil }.accessibilityIdentifier("tag-delete-confirm") }
                Button("キャンセル", role: .cancel) { removing = nil }
            } message: { Text("「\(removing ?? "")」と子タグをすべてのノートから外します。ノートやカードは削除しません。") }
            .alert("タグを変更できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .interactiveDismissDisabled(busy)
        }
    }
    private func reload() async {
        do { tree = TagTreeEntry.flatten(try await model.engine.call("TagsService.TagTree")) }
        catch { self.error = error.localizedDescription }
    }
    private func setCollapsed(_ entry: TagTreeEntry) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await model.engine.call("TagsService.SetTagCollapsed", ["name": entry.name, "collapsed": !entry.collapsed])
                await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func run(_ method: String, _ input: [String: Any] = [:], backup: Bool = true) {
        guard !busy else { return }
        busy = true
        let engine = model.engine
        Task {
            defer { busy = false }
            do {
                if backup { try await engine.backup() }
                _ = try await engine.call(method, input)
                await reload()
                model.refreshAfterEditing()
            } catch { self.error = error.localizedDescription }
        }
    }
}
private struct TagEditForm: View {
    let request: TagEditRequest
    let save: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var busy = false
    @State private var error: String?
    init(request: TagEditRequest, save: @escaping (String) async throws -> Void) {
        self.request = request; self.save = save
        _value = State(initialValue: request.moving ? "" : request.tag)
    }
    var body: some View {
        NavigationStack {
            Form {
                Text(request.tag)
                TextField(request.moving ? "移動先の親タグ（空欄で最上位）" : "新しいタグ名", text: $value)
                    .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("tag-edit-name")
                Text("子タグとノートに付いているタグも変更します。")
                if busy { ProgressView() }
            }.disabled(busy)
            .studyThemeSurface().navigationTitle(request.moving ? "タグを移動" : "タグ名を変更")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("適用") {
                    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard (request.moving || !cleaned.isEmpty), !cleaned.contains(where: \.isWhitespace),
                          cleaned.isEmpty || !cleaned.components(separatedBy: "::").contains("") else {
                        error = "空白や空の階層を含まないタグ名を入力してください。"; return
                    }
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await save(cleaned); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy).accessibilityIdentifier("tag-edit-apply") }
            }
            .interactiveDismissDisabled(busy)
            .alert("タグを変更できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
