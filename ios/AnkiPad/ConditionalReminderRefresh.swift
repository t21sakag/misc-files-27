import Foundation
import UIKit

extension StudyModel {
    func scheduleConditionalReminderRefresh() {
        reminderRefreshTask?.cancel()
        let generation = UUID()
        reminderRefreshGeneration = generation
        guard profilesReady else { return }
        let profile = currentProfile, engine = self.engine
        reminderRefreshTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard currentProfileID == profile.id, !busy, !showingSettings, !showingProfiles else { return }
                let config = try ReviewReminderStore.load(profileID: profile.id)
                guard config.enabled, config.conditional else { return }
                let lease = UIApplication.shared.beginBackgroundTask(withName: "Refresh reminders") { Task { @MainActor in if self.reminderRefreshGeneration == generation { self.reminderRefreshTask?.cancel() } } }
                defer { if lease != .invalid { UIApplication.shared.endBackgroundTask(lease) } }
                try await ReviewReminderStore.save(config, profile: profile, engine: engine, requestPermission: false)
                if currentProfileID == profile.id { reminderUpdateError = nil }
            } catch is CancellationError {} catch {
                if currentProfileID == profile.id { reminderUpdateError = "条件付き通知を更新できませんでした。通知設定を確認してください。" }
            }
        }
    }
}
