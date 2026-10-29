import Foundation
#if os(iOS) || ANKIPAD_PARSE_UI
import SwiftUI
#endif

struct ReviewToolbarItem: Codable, Identifiable {
    var id = UUID()
    var action: ReviewGestureAction
}
struct ReviewToolbarConfiguration: Codable {
    var enabled = false
    var items = [ReviewGestureAction.replay, .undo, .mark, .edit].map { ReviewToolbarItem(action: $0) }
    static let maximumItems = 12
    static func load(_ data: Data? = UserDefaults.standard.data(forKey: "reviewToolbarConfiguration")) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.items.count <= maximumItems, Set(value.items.map(\.id)).count == value.items.count else { return Self() }
        return value
    }
}
#if os(iOS) || ANKIPAD_PARSE_UI
struct ReviewToolbarSettingsView: View {
    @Binding var configuration: ReviewToolbarConfiguration
    var body: some View {
        List {
            Section {
                Toggle("追加の操作バーを表示", isOn: $configuration.enabled).accessibilityIdentifier("toolbar-enabled")
            }
            Section("表示する操作と順序") {
                ForEach($configuration.items) { $item in
                    Picker("操作", selection: $item.action) {
                        ForEach(ReviewGestureAction.allCases) { action in Text(action.title).tag(action) }
                    }
                }
                .onDelete { configuration.items.remove(atOffsets: $0) }
                .onMove { configuration.items.move(fromOffsets: $0, toOffset: $1) }
                Button("操作を追加", systemImage: "plus") { configuration.items.append(ReviewToolbarItem(action: .replay)) }
                    .disabled(configuration.items.count >= ReviewToolbarConfiguration.maximumItems)
            }
            Section {
                Text("編集を押すと操作を並べ替え・削除できます。操作バーは通常表示で使えます。")
                Button("初期設定に戻す") { configuration = ReviewToolbarConfiguration() }
            }
        }
        .studyThemeSurface().navigationTitle("操作バーの設定")
        .toolbar { EditButton() }
    }
}

#endif
