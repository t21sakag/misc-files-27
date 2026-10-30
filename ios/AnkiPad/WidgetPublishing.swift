import Foundation
import WidgetKit

extension StudyModel {
    /// Invalidate work before any collection operation/profile transition. A
    /// cancelled old engine must never publish into a newer profile's display.
    func scheduleWidgetRefresh(force: Bool = false) {
        if force { widgetRefreshNeeded = true }
        widgetRefreshTask?.cancel()
        let generation = UUID(); widgetRefreshGeneration = generation
        guard widgetRefreshNeeded, profilesReady, !busy, !isSyncing, let container = SharedGroup.container() else { return }
        #if DEBUG
        let namespace = UITestIsolation.namespace()
        #else
        let namespace: String? = nil
        #endif
        let store = WidgetSnapshotStore(directory: WidgetSnapshotStore.directory(in: container, testingNamespace: namespace))
        let engine = engine, registry = profileRegistry
        widgetRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard let self, self.widgetRefreshGeneration == generation, !self.busy else { return }
                // Widgets can run before, or without, visiting the share inbox.
                // Publish their language and Debug data scope before reloading
                // a timeline; the inbox controller is not a prerequisite.
                try SharedClientSettings.save(language: AppText.language, in: container, testingNamespace: namespace)
                let previous = try? store.load()
                let profiles = registry.profiles.map { WidgetProfileSnapshot(id: $0.id, name: $0.name, collection: nil) }
                // Publish the committed registry before a possibly failing
                // engine read; deleted profiles must not linger in the widget.
                let index = WidgetSnapshot.updating(previous, profiles: profiles, selectedID: registry.selectedID,
                    collection: previous?.profiles.first { $0.id == registry.selectedID }?.collection)
                if index != previous {
                    try store.save(index)
                    self.reloadStudyWidgets()
                }
                let snapshot = try await engine.widgetSnapshot()
                try Task.checkCancellation()
                guard self.widgetRefreshGeneration == generation, !self.busy, !self.isSyncing,
                      self.currentProfileID == registry.selectedID, self.engine === engine else { return }
                let value = WidgetSnapshot.updating(previous, profiles: profiles, selectedID: registry.selectedID, collection: snapshot)
                // No suspension between the generation guard and atomic publish.
                try store.save(value)
                #if DEBUG
                if UITestIsolation.namespace() != nil, ProcessInfo.processInfo.arguments.contains("--uitest-widgets"), let stored = try store.load() {
                    self.widgetSnapshotInspection = String(data: try JSONEncoder().encode(stored), encoding: .utf8) ?? ""
                }
                #endif
                self.widgetRefreshNeeded = false
                self.widgetRefreshError = nil
                self.reloadStudyWidgets()
            } catch is CancellationError {} catch {
                guard let self, self.widgetRefreshGeneration == generation else { return }
                self.widgetRefreshError = error.localizedDescription
            }
        }
    }

    private func reloadStudyWidgets() {
        for kind in ["study.summary", "study.decks", "study.analysis", "study.add"] {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    func openWidgetRoute(_ route: WidgetRoute) async throws {
        guard profilesReady, !busy, !widgetNavigationActive else { return }
        guard profileRegistry.profiles.contains(where: { $0.id == route.profileID }) else {
            throw ProfileRegistryError(message: AppText.localized("ウィジェットのプロファイルが見つかりません。ウィジェットを設定し直してください。"))
        }
        widgetNavigationActive = true
        defer { widgetNavigationActive = false; processPendingAutomaticSync() }
        try await switchProfile(route.profileID)
        // Keep the gate across the fresh lookup and opening the destination.
        // A stale/missing deck must never fall back to a different deck.
        busy = true
        defer { busy = false }
        leave()
        decks = try await engine.decks()
        let deck = route.deckID.flatMap { id in decks.first { $0.id == id } }
        if route.deckID != nil && deck == nil {
            throw EngineError(message: AppText.localized("ウィジェットのデッキが見つかりません。ウィジェットを設定し直してください。"))
        }
        switch route.destination {
        case .home: break
        case .add: editorRequest = EditorRequest(deckID: deck?.id ?? "0")
        case .options:
            if let deck { backendPage = BackendPageRequest(path: "deck-options/" + deck.id, title: AppText.localized("デッキオプション")) }
        case .review:
            if let deck { try await startReview(deck) }
        }
    }
}
