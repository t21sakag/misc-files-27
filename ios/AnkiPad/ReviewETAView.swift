import SwiftUI

// Use the same history and queue estimate as the card API. This is a forecast,
// not a countdown; refresh when the scheduler supplies a new card state.
struct ReviewETAView: View {
    let engine: Engine
    let cardKey: String
    @State private var minutes: Int?

    var body: some View {
        Text(minutes.map { AppText.localized("残り約\($0)分") } ?? AppText.localized("残り時間: —"))
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .accessibilityIdentifier("review-eta")
            .task(id: cardKey) {
                minutes = nil
                let estimate = try? await engine.ankiDroidETA()
                guard !Task.isCancelled else { return }
                minutes = estimate.flatMap { $0 >= 0 ? $0 : nil }
            }
    }
}
