import SwiftUI

struct CustomStudyRequest: Identifiable {
    let id = UUID()
    let deck: Deck
}
struct CustomStudyView: View {
    @ObservedObject var model: StudyModel
    let request: CustomStudyRequest
    @Environment(\.dismiss) private var dismiss
    @State private var action = "newLimitDelta"
    @State private var amount = 10
    @State private var limit = 100
    @State private var include = ""
    @State private var exclude = ""
    @State private var kind = "CRAM_KIND_DUE"
    @State private var available = ""
    @State private var busy = false
    @State private var error: String?
    private let actions = [("newLimitDelta", "今日の新規カード上限を増やす"), ("reviewLimitDelta", "今日の復習上限を増やす"), ("forgotDays", "最近忘れたカードを復習"), ("reviewAheadDays", "先の日付のカードを復習"), ("previewDays", "最近追加したカードをプレビュー"), ("cram", "状態・タグで選んで学習")]
    var body: some View {
        NavigationStack {
            Form {
                Section(request.deck.name) {
                    Picker("学習方法", selection: $action) { ForEach(actions, id: \.0) { Text($0.1).tag($0.0) } }
                    if action == "cram" {
                        Picker("対象", selection: $kind) {
                            Text("期日到来").tag("CRAM_KIND_DUE"); Text("新規").tag("CRAM_KIND_NEW")
                            Text("復習").tag("CRAM_KIND_REVIEW"); Text("すべて（予定を変更しない）").tag("CRAM_KIND_ALL")
                        }
                        Stepper("最大 \(limit)枚", value: $limit, in: 1...10000)
                        TextField("含めるタグ（空白区切り）", text: $include)
                        TextField("除外するタグ（空白区切り）", text: $exclude)
                    } else {
                        Stepper("\(amount)\(action.hasSuffix("Delta") ? "枚" : "日")", value: $amount, in: 1...10000)
                    }
                    if !available.isEmpty { Text(available).foregroundStyle(.secondary) }
                }
                if busy { ProgressView() }
            }
            .disabled(busy)
            .navigationTitle("カスタム学習")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("作成") { perform() }.disabled(busy) }
            }
            .task {
                do {
                    let defaults = try await model.engine.call("SchedulerService.CustomStudyDefaults", ["deckId": request.deck.id])
                    available = "利用できる新規: \(defaults["availableNew"] as? Int ?? 0)枚、復習: \(defaults["availableReview"] as? Int ?? 0)枚"
                } catch { self.error = error.localizedDescription }
            }
            .alert("学習を作成できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("閉じる", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func perform() {
        busy = true
        Task {
            defer { busy = false }
            do {
                var input: [String: Any] = ["deckId": request.deck.id]
                if action == "cram" {
                    input["cram"] = ["kind": kind, "cardLimit": limit, "tagsToInclude": include.split(whereSeparator: \.isWhitespace).map(String.init), "tagsToExclude": exclude.split(whereSeparator: \.isWhitespace).map(String.init)]
                } else { input[action] = amount }
                try await model.engine.backup()
                _ = try await model.engine.call("SchedulerService.CustomStudy", input)
                model.refreshAfterEditing()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct FilteredDeckRequest: Identifiable {
    let id = UUID()
    var deckID = "0"
}
struct FilteredDeckView: View {
    @ObservedObject var model: StudyModel
    let request: FilteredDeckRequest
    @Environment(\.dismiss) private var dismiss
    @State private var raw: [String: Any] = [:]
    @State private var config: [String: Any] = [:]
    @State private var name = ""
    @State private var query = "is:due"
    @State private var secondQuery = ""
    @State private var secondEnabled = false
    @State private var limit = 100
    @State private var secondLimit = 100
    @State private var order = 0
    @State private var secondOrder = 0
    @State private var labels: [String] = []
    @State private var reschedule = true
    @State private var again = 60
    @State private var hard = 600
    @State private var good = 0
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    private let orders = ["OLDEST_REVIEWED_FIRST", "RANDOM", "INTERVALS_ASCENDING", "INTERVALS_DESCENDING", "LAPSES", "ADDED", "DUE", "REVERSE_ADDED", "RETRIEVABILITY_ASCENDING", "RETRIEVABILITY_DESCENDING", "RELATIVE_OVERDUENESS"]
    var body: some View {
        NavigationStack {
            Form {
                TextField("デッキ名", text: $name)
                Section("検索条件") {
                    TextField("検索", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Stepper("上限 \(limit)枚", value: $limit, in: 1...100000)
                    orderPicker($order)
                }
                Toggle("2つ目の検索条件", isOn: $secondEnabled)
                if secondEnabled {
                    Section("2つ目の検索条件") {
                        TextField("検索", text: $secondQuery).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Stepper("上限 \(secondLimit)枚", value: $secondLimit, in: 1...100000)
                        orderPicker($secondOrder)
                    }
                }
                Toggle("解答に基づいて学習予定を更新", isOn: $reschedule)
                if !reschedule {
                    Stepper("もう一度: \(again)秒", value: $again, in: 0...86400)
                    Stepper("難しい: \(hard)秒", value: $hard, in: 0...86400)
                    Stepper("普通: \(good)秒（0で元のデッキに戻す）", value: $good, in: 0...86400)
                }
                if busy { ProgressView() }
            }
            .disabled(busy || !loaded)
            .navigationTitle("フィルターデッキ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("構築") { save() }.disabled(busy || !loaded || name.isEmpty) }
            }
            .task { await load() }
            .alert("構築できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("閉じる", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func orderPicker(_ selection: Binding<Int>) -> some View {
        Picker("抽出順", selection: selection) { ForEach(orders.indices, id: \.self) { Text(labels.indices.contains($0) ? labels[$0] : orders[$0]).tag($0) } }
    }
    private func load() async {
        do {
            raw = try await model.engine.call("DecksService.GetOrCreateFilteredDeck", ["did": request.deckID])
            config = raw["config"] as? [String: Any] ?? [:]
            name = raw["name"] as? String ?? "フィルターデッキ"
            labels = try await model.engine.call("DecksService.FilteredDeckOrderLabels")["vals"] as? [String] ?? []
            let terms = config["searchTerms"] as? [[String: Any]] ?? []
            if let first = terms.first { query = first["search"] as? String ?? ""; limit = first["limit"] as? Int ?? 100; order = orders.firstIndex(of: first["order"] as? String ?? "") ?? 0 }
            if terms.count > 1 { let term = terms[1]; secondEnabled = true; secondQuery = term["search"] as? String ?? ""; secondLimit = term["limit"] as? Int ?? 100; secondOrder = orders.firstIndex(of: term["order"] as? String ?? "") ?? 0 }
            reschedule = config["reschedule"] as? Bool ?? false
            again = config["previewAgainSecs"] as? Int ?? 0; hard = config["previewHardSecs"] as? Int ?? 0; good = config["previewGoodSecs"] as? Int ?? 0
            loaded = true
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                var terms: [[String: Any]] = [["search": query, "limit": limit, "order": orders[order]]]
                if secondEnabled { terms.append(["search": secondQuery, "limit": secondLimit, "order": orders[secondOrder]]) }
                config["searchTerms"] = terms; config["reschedule"] = reschedule
                config["previewAgainSecs"] = again; config["previewHardSecs"] = hard; config["previewGoodSecs"] = good
                raw["name"] = name; raw["config"] = config; raw["allowEmpty"] = true
                try await model.engine.backup()
                let result = try await model.engine.call("DecksService.AddOrUpdateFilteredDeck", raw)
                _ = try await model.engine.call("SchedulerService.RebuildFilteredDeck", ["did": result["id"] as? String ?? request.deckID])
                model.refreshAfterEditing()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
