import Foundation

extension StudyModel {
    func logout() {
        guard !busy else { return }
        do {
            try AccountStore.delete(profileID: currentProfileID)
            account = nil
            lastSync = nil
            syncStatus = ""
            // A prepared replacement belongs to the account that supplied it.
            // Never offer its directions/server USN after changing accounts.
            syncDecision = nil
            chooseFullSync = false
            confirmDirection = nil
            meteredSyncPrompt = false
            UserDefaults.standard.removeObject(forKey: profilePreferenceKey("lastSync"))
        } catch { self.error = error.localizedDescription }
    }
}
