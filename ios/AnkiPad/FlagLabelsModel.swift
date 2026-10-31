import Foundation

extension StudyModel {
    func scheduleFlagLabelRefresh() {
        flagLabelRefreshTask?.cancel()
        let source = engine
        if flagLabelSource !== source {
            if flagLabels != FlagLabels() { flagLabels = FlagLabels() }
            flagLabelSource = source
        }
        flagLabelRefreshTask = Task { [weak self] in
            do {
                let labels = try await source.flagLabels()
                try Task.checkCancellation()
                guard let self, self.engine === source else { return }
                if self.flagLabels != labels { self.flagLabels = labels }
            } catch is CancellationError {} catch {
                guard let self, self.engine === source, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func loadFlagLabels() async throws {
        let source = engine
        let labels = try await source.flagLabels()
        try Task.checkCancellation()
        guard engine === source else { throw CancellationError() }
        if flagLabels != labels { flagLabels = labels }
    }
    func renameFlag(_ code: Int, name: String) async throws {
        guard profilesReady, !busy else { throw EngineError(message: AppText.localized("処理が終わってからもう一度選んでください。")) }
        busy = true
        defer {
            busy = false
            scheduleConditionalReminderRefresh()
            showInterruptedSyncIfNeeded()
            processPendingAutomaticSync()
        }
        flagLabelRefreshTask?.cancel()
        let labels = try await engine.renameFlag(code, name: name)
        if flagLabels != labels { flagLabels = labels }
        localSyncState = try? await engine.localSyncState().applyingCleanStamp(UserDefaults.standard.string(forKey: profilePreferenceKey("syncCleanStamp")))
    }
}
