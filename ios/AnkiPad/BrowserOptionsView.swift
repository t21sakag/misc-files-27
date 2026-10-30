import SwiftUI

struct BrowserOptionsView: View {
    @ObservedObject var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var options = BrowserOptions()
    @State private var truncate = UserDefaults.standard.bool(forKey: "isTruncated")
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?

    #if DEBUG
    @State private var traceInstance = UUID()
    #endif
    private func trace(_ phase: String) {
        #if DEBUG
        guard UITestIsolation.namespace() != nil else { return }
        NSLog("browser.options.trace instance=%@ phase=%@ loaded=%d busy=%d truncate=%d notes=%d accents=%d",
              traceInstance.uuidString, phase, loaded ? 1 : 0, busy ? 1 : 0,
              truncate ? 1 : 0, options.notesMode ? 1 : 0, options.ignoreAccents ? 1 : 0)
        #endif
    }
    private var truncationBinding: Binding<Bool> {
        Binding(get: { truncate }, set: { value in
            trace(value ? "truncate.set.true" : "truncate.set.false")
            truncate = value
            trace("truncate.assigned")
        })
    }
    private func optionBinding(_ keyPath: WritableKeyPath<BrowserOptions, Bool>, name: String) -> Binding<Bool> {
        Binding(get: { options[keyPath: keyPath] }, set: { value in
            trace(name + (value ? ".set.true" : ".set.false"))
            options[keyPath: keyPath] = value
            trace(name + ".assigned")
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.localized("表示")) {
                    Toggle(AppText.localized("ノート表示"), isOn: optionBinding(\.notesMode, name: "notes")).accessibilityIdentifier("browser-options-notes")
                    Toggle(AppText.localized("長い内容を3行で省略"), isOn: truncationBinding).accessibilityIdentifier("browser-options-truncate")
                    Text(AppText.localized("省略しない場合は、ブラウザーの各列に内容全体を表示します。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(AppText.localized("検索")) {
                    Toggle(AppText.localized("検索でアクセントを区別しない"), isOn: optionBinding(\.ignoreAccents, name: "accents"))
                        .accessibilityIdentifier("browser-options-ignore-accents")
                    TextField(AppText.localized("既定の検索"), text: $options.defaultSearch)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("browser-options-default-search")
                    Text(AppText.localized("次にブラウザーを開いたときに使います。明示して渡された検索条件は優先されます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if busy { ProgressView() }
            }
            .disabled(!loaded || busy)
            .studyThemeSurface().navigationTitle(AppText.localized("ブラウザーの設定"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.localized("キャンセル")) { dismiss() }.disabled(busy).accessibilityIdentifier("browser-options-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.localized("保存")) { save() }.disabled(!loaded || busy).accessibilityIdentifier("browser-options-save")
                }
            }
            .interactiveDismissDisabled(busy)
            #if DEBUG
            .background {
                if UITestIsolation.namespace() != nil {
                    BrowserOptionsHitProbe().frame(width: 0, height: 0).allowsHitTesting(false)
                }
            }
            #endif
            .onAppear { trace("appear") }
            .onDisappear { trace("disappear") }
            .onChange(of: truncate) { _, _ in trace("truncate.changed") }
            .task {
                trace("load.start")
                do { options = try await model.engine.browserOptions(); loaded = true; trace("load.end") }
                catch { self.error = error.localizedDescription }
            }
            .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard loaded, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.engine.saveBrowserOptions(options)
                UserDefaults.standard.set(truncate, forKey: "isTruncated")
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
