#if DEBUG
import SwiftUI

/// Diagnostic only: retain the original Form's sections and native controls,
/// but render them eagerly without recycled list cells. Production keeps its
/// platform Form until rendering, labels, navigation and persistence are proved.
struct ToolbarEagerFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections: configuration.content.labeledContentStyle(ToolbarEagerLabeledContentStyle())) { section in
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
        // Keep choices as native menus; nested destination Forms retain their
        // ordinary platform style rather than inheriting this experiment.
        .pickerStyle(.menu)
        .formStyle(.automatic)
    }
}

/// Form's platform renderer normally supplies this visual label/value layout.
/// Apply the style before resolving subviews so labels are retained alongside
/// native pickers and text fields, rather than only in accessibility metadata.
private struct ToolbarEagerLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            configuration.content
        }
    }
}
#endif
