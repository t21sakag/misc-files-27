import SwiftUI

/// Keep native settings controls mounted while navigating to child screens.
/// All section headers, controls and footers retain their original bindings.
struct SettingsForm<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections: content) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.header.isEmpty {
                            VStack(alignment: .leading) { section.header }
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.horizontal, 16)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(section.content) { row in
                                row.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                if row.id != section.content.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        if !section.footer.isEmpty {
                            VStack(alignment: .leading) { section.footer }
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 20)
        }
        .accessibilityIdentifier("settings-eager-scroll")
    }
}
