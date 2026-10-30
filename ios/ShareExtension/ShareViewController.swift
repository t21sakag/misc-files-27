import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var model: ShareComposer?
    override func viewDidLoad() {
        super.viewDidLoad()
        let container = SharedGroup.container()
        if let container, let settings = SharedClientSettings.load(from: container) {
            UserDefaults.standard.set(settings.language, forKey: AppLanguageChoice.preferenceKey)
        }
        let model = ShareComposer(container: container)
        self.model = model
        let host = UIHostingController(rootView: ShareComposerView(model: model, cancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }, complete: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }).environment(\.locale, AppText.locale))
        addChild(host); host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        model.load(extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
    }
}

@MainActor final class ShareComposer: ObservableObject {
    @Published var subject = ""
    @Published var text = ""
    @Published var tags = ""
    @Published var isHTML = false
    @Published private(set) var loading = true
    @Published private(set) var publishing = false
    @Published private(set) var published = false
    @Published var error: String?
    @Published private(set) var files: [ShareProviderFile] = []
    private let container: URL?
    private let inboxRoot: URL?
    private var loadFailed = false
    var available: Bool { container != nil && !loadFailed }
    init(container: URL?) {
        self.container = container
        inboxRoot = container.map { SharedClientSettings.extensionInboxDirectory(in: $0) }
    }
    func load(_ items: [NSExtensionItem]) {
        Task {
            defer { loading = false }
            do {
                var parts: [String] = []
                for item in items {
                    if subject.isEmpty { subject = item.attributedTitle?.string ?? "" }
                    if let value = item.attributedContentText?.string, !value.isEmpty { parts.append(value) }
                    for provider in item.attachments ?? [] {
                        if let type = ShareProviderFile.preferredType(provider) {
                            guard files.isEmpty else { throw ShareInputError.multipleFiles }
                            files.append(try await ShareProviderFile.load(provider, type: type))
                        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                            let value = try await Self.value(from: provider, type: UTType.url.identifier)
                            if !value.isEmpty && !parts.contains(value) { parts.append(value) }
                        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                            let value = try await Self.value(from: provider, type: UTType.plainText.identifier)
                            if !value.isEmpty && !parts.contains(value) { parts.append(value) }
                        }
                    }
                }
                text = parts.joined(separator: "\n")
                if container == nil { error = AppText.localized("共有の保存先を開けませんでした。アプリを開き直しても改善しない場合は再署名してください。") }
                else if subject.isEmpty && text.isEmpty && files.isEmpty { error = AppText.localized("共有するテキストが見つかりませんでした。") }
            } catch {
                loadFailed = true
                files = []
                if error is ShareInputError { self.error = AppText.localized("ファイルは1つずつ共有してください。") }
                else { self.error = AppText.localized("共有内容を読み込めませんでした。もう一度共有してください。") }
            }
        }
    }
    private enum ShareInputError: Error { case multipleFiles }
    private static func value(from provider: NSItemProvider, type: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { continuation.resume(throwing: error); return }
                if let value = value as? URL { continuation.resume(returning: value.absoluteString) }
                else if let value = value as? String { continuation.resume(returning: value) }
                else if let value = value as? Data, let string = String(data: value, encoding: .utf8) { continuation.resume(returning: string) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
    }
    func publish() {
        guard available, !loading, !publishing, !published, let inboxRoot, !subject.isEmpty || !text.isEmpty || !files.isEmpty else { return }
        publishing = true
        let content = SharedTextContent(subject: subject, text: text, tags: tags.isEmpty ? nil : tags, isHTML: isHTML)
        let leases = files
        Task {
            defer { publishing = false }
            do {
                _ = try await Task.detached(priority: .utility) {
                    try SharedInbox(root: inboxRoot).publish(text: content, files: leases.map(\.file))
                }.value
                published = true
            } catch { self.error = AppText.localized("共有内容を保存できませんでした。元のアプリからもう一度共有してください。") }
        }
    }
}

struct ShareComposerView: View {
    @ObservedObject var model: ShareComposer
    let cancel: () -> Void
    let complete: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                if model.published {
                    Section {
                        Text(AppText.localized("共有内容を保存しました"))
                        Text(AppText.localized("次にAnkiPadを開くと編集できます。"))
                    }
                } else {
                    if model.loading { ProgressView(AppText.localized("共有を受信しています…")) }
                    if !model.files.isEmpty {
                        Section(AppText.localized("ファイル")) {
                            ForEach(model.files.indices, id: \.self) { index in
                                Text(model.files[index].file.name).accessibilityIdentifier("share-file-" + String(index))
                            }
                        }
                    }
                    Section(AppText.localized("件名（任意）")) {
                        TextField(AppText.localized("表面"), text: $model.subject).accessibilityIdentifier("share-subject")
                    }
                    Section(AppText.localized("テキスト")) {
                        TextEditor(text: $model.text).frame(minHeight: 180).accessibilityIdentifier("share-text")
                    }
                    Section {
                        TextField(AppText.localized("タグ（空白で区切る）"), text: $model.tags)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle(AppText.localized("HTMLとして取り込む"), isOn: $model.isHTML)
                        Text(AppText.localized("次にAnkiPadを開くと編集できます。"))
                    }
                }
            }
            .disabled(model.loading || model.publishing)
            .navigationTitle("AnkiPad")
            .toolbar {
                if model.published {
                    ToolbarItem(placement: .confirmationAction) { Button(AppText.localized("完了"), action: complete).accessibilityIdentifier("share-complete") }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button(AppText.localized("キャンセル"), action: cancel).disabled(model.publishing) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppText.localized("送信")) { model.publish() }
                            .disabled(!model.available || model.loading || model.publishing || (model.subject.isEmpty && model.text.isEmpty && model.files.isEmpty))
                            .accessibilityIdentifier("share-submit")
                    }
                }
            }
            .alert(AppText.localized("処理できませんでした"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(AppText.localized("閉じる"), role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}
