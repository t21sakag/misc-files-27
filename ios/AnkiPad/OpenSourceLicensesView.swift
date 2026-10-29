import SwiftUI
import UIKit

struct OpenSourceLicensesView: View {
    private let entries = [
        ("Anki / Ankitects のライセンス表記", "Anki-NOTICE", "txt", false),
        ("GNU AGPL v3", "AGPL-3.0", "txt", false),
        ("AnkiDroid / GNU GPL v3", "AnkiDroid-GPL-3.0", "txt", false),
        ("Web表示の依存ライブラリ", "licenses-ts", "json", true),
        ("エンジンの依存ライブラリ", "licenses-cargo", "json", true),
    ]
    private var sourceURL: URL {
        let commit = Bundle.main.object(forInfoDictionaryKey: "AnkiPadSourceCommit") as? String ?? ""
        let ref = commit.count == 40 && commit.allSatisfy(\.isHexDigit) ? commit : "main"
        return URL(string: "https://github.com/t21sakag/misc-files-27/tree/" + ref)!
    }
    var body: some View {
        List {
            ForEach(entries, id: \.1) { entry in
                NavigationLink(entry.0) {
                    LicenseDocumentView(name: entry.1, ext: entry.2, backend: entry.3).studyThemeSurface().navigationTitle(entry.0).navigationBarTitleDisplayMode(.inline)
                }
            }
            Link("ソースコード", destination: sourceURL)
        }.studyThemeSurface().navigationTitle("ライセンスとソース")
    }
}
private struct LicenseDocumentView: View {
    let name: String
    let ext: String
    let backend: Bool
    @State private var text = ""
    var body: some View {
        ReadOnlyLicenseText(text: text)
            .task {
                do {
                    guard let url = backend ? Bundle.main.resourceURL?.appendingPathComponent("backend/\(name).\(ext)") : Bundle.main.url(forResource: name, withExtension: ext) else { throw EngineError(message: "ライセンスを読み込めませんでした。") }
                    text = try String(contentsOf: url, encoding: .utf8)
                } catch { text = error.localizedDescription }
            }
    }
}
private struct ReadOnlyLicenseText: UIViewRepresentable {
    @AppStorage("dayTheme") private var day = "1"
    @AppStorage("nightTheme") private var night = "3"
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        let theme = StudyTheme.resolve(dark: view.traitCollection.userInterfaceStyle == .dark, day: day, night: night)
        view.backgroundColor = theme.nativeBackground
        view.textColor = .label
    }
}
