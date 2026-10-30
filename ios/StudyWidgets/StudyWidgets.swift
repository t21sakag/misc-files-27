import SwiftUI
import WidgetKit

@main struct StudyWidgets: WidgetBundle {
    init() { WidgetData.prepareLanguage() }
    var body: some Widget {
        StudySummaryWidget()
        StudyDeckListWidget()
        StudyDeckAnalysisWidget()
        StudyAddNoteWidget()
    }
}

struct StudySummaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "study.summary", intent: ProfileWidgetConfiguration.self, provider: ProfileWidgetProvider()) { entry in
            StudySummaryView(entry: entry).environment(\.locale, AppText.locale)
        }
        .configurationDisplayName(Text(AppText.localized("学習状況")))
        .description(Text(AppText.localized("残りのカード数と所要時間を表示します。")))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct StudyDeckListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "study.decks", intent: DeckListWidgetConfiguration.self, provider: DeckListWidgetProvider()) { entry in
            StudyDeckListView(entry: entry).environment(\.locale, AppText.locale)
        }
        .configurationDisplayName(Text(AppText.localized("デッキ一覧")))
        .description(Text(AppText.localized("選択したデッキの枚数を順番に表示し、タップで開きます。")))
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}
struct StudyDeckAnalysisWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "study.analysis", intent: DeckAnalysisWidgetConfiguration.self, provider: DeckAnalysisWidgetProvider()) { entry in
            StudyDeckAnalysisView(entry: entry).environment(\.locale, AppText.locale)
        }
        .configurationDisplayName(Text(AppText.localized("デッキの枚数")))
        .description(Text(AppText.localized("1つのデッキの新規・学習・復習の枚数を表示します。")))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct StudyAddNoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "study.add", intent: ProfileWidgetConfiguration.self, provider: ProfileWidgetProvider()) { entry in
            StudyAddNoteView(entry: entry).environment(\.locale, AppText.locale)
        }
        .configurationDisplayName(Text(AppText.localized("ノートを追加")))
        .description(Text(AppText.localized("選択したプロファイルで新しいノートを開きます。")))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WidgetUnavailableView: View {
    var configure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AnkiPad", systemImage: "rectangle.stack").font(.headline)
            Text(configure ? AppText.localized("ウィジェットを編集してデッキを選択してください。") : AppText.localized("アプリを開いてウィジェットを更新してください。"))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
private struct WidgetUpdatedView: View {
    let collection: WidgetCollectionSnapshot
    var body: some View {
        HStack(spacing: 3) {
            Text(AppText.localized("更新:"))
            Text(collection.updatedAt, style: .time)
        }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
}
private struct WidgetCountView: View {
    let counts: WidgetCounts
    var body: some View {
        HStack(spacing: 12) {
            value(counts.new, title: AppText.localized("新規"), color: .blue)
            value(counts.learning, title: AppText.localized("学習"), color: .orange)
            value(counts.review, title: AppText.localized("復習"), color: .green)
        }.monospacedDigit()
    }
    private func value(_ count: Int, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(count.formatted()).font(.title3.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }
}

struct StudySummaryView: View {
    let entry: StudyWidgetEntry
    var body: some View {
        Group {
            if let profile = entry.profile, let collection = profile.collection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name).font(.headline).lineLimit(1)
                    if collection.isCurrent(at: entry.date) {
                        if collection.counts.total == 0 {
                            Label(AppText.localized("今日の学習は完了"), systemImage: "checkmark.circle").font(.headline)
                        } else {
                            Text(AppText.localized("残り\(collection.counts.total)枚")).font(.title2.bold()).minimumScaleFactor(0.7).lineLimit(1)
                                .accessibilityIdentifier("widget-summary-remaining")
                            if let minutes = collection.etaMinutes { Text(AppText.localized("約\(minutes)分")).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    } else { Text(AppText.localized("アプリを開いて更新")) }
                    Spacer(minLength: 0)
                    WidgetUpdatedView(collection: collection)
                }.privacySensitive()
            } else { WidgetUnavailableView() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(entry.homeURL).containerBackground(.background, for: .widget)
    }
}

struct StudyDeckListView: View {
    let entry: StudyWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var capacity: Int {
        let rows = family == .systemMedium ? 3 : (family == .systemLarge ? 8 : 12)
        return dynamicTypeSize.isAccessibilitySize ? max(1, rows / 2) : rows
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.deckIDs.isEmpty { WidgetUnavailableView(configure: true) }
            else {
                Text(AppText.localized("デッキ一覧")).font(.headline)
                ForEach(Array(entry.deckIDs.prefix(capacity).enumerated()), id: \.offset) { _, id in
                    if let (profile, deck) = WidgetData.deck(id, in: entry.snapshot), let collection = profile.collection {
                        Link(destination: WidgetRoute(profileID: profile.id, deckID: deck.id,
                            destination: deck.counts.total == 0 ? .options : .review).url) {
                            HStack {
                                Text(deck.name).lineLimit(1)
                                Spacer(minLength: 4)
                                if collection.isCurrent(at: entry.date) {
                                    Text(deck.counts.new.formatted()).foregroundStyle(.blue)
                                    Text(deck.counts.learning.formatted()).foregroundStyle(.orange)
                                    Text(deck.counts.review.formatted()).foregroundStyle(.green)
                                } else { Image(systemName: "arrow.clockwise") }
                            }.font(.subheadline).monospacedDigit().frame(minHeight: 24)
                        }.privacySensitive()
                    } else { Text(AppText.localized("デッキが見つかりません")).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Text(AppText.localized("件数はアプリで取得した時点の値です。")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).containerBackground(.background, for: .widget)
    }
}

struct StudyDeckAnalysisView: View {
    let entry: StudyWidgetEntry
    private var deck: (WidgetProfileSnapshot, WidgetDeckSnapshot)? { entry.deckIDs.first.flatMap { WidgetData.deck($0, in: entry.snapshot) } }
    private var destination: URL? {
        deck.map { WidgetRoute(profileID: $0.0.id, deckID: $0.1.id, destination: $0.1.counts.total == 0 ? .options : .review).url }
    }
    var body: some View {
        Group {
            if let (profile, deck) = deck, let collection = profile.collection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(deck.name).font(.headline).lineLimit(2)
                    Text(profile.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if collection.isCurrent(at: entry.date) { WidgetCountView(counts: deck.counts) }
                    else { Text(AppText.localized("アプリを開いて更新")) }
                    Spacer(minLength: 0)
                    WidgetUpdatedView(collection: collection)
                }.privacySensitive()
            } else { WidgetUnavailableView(configure: true) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(destination).containerBackground(.background, for: .widget)
    }
}

struct StudyAddNoteView: View {
    let entry: StudyWidgetEntry
    var body: some View {
        Group {
            if let profile = entry.profile {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "plus.rectangle.on.rectangle").font(.largeTitle).foregroundStyle(.tint)
                    Text(AppText.localized("ノートを追加")).font(.headline)
                    Text(profile.name).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                }
            } else { WidgetUnavailableView() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(entry.profile.map { WidgetRoute(profileID: $0.id, destination: .add).url })
            .containerBackground(.background, for: .widget)
    }
}
