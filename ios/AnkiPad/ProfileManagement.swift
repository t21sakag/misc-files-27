import Foundation

extension StudyModel {
    var currentProfileID: String { profileRegistry.selectedID }
    var currentProfile: StudyProfile { profileRegistry.profiles.first { $0.id == currentProfileID } ?? .legacy }
    func profilePreferenceKey(_ key: String, profileID: String? = nil) -> String {
        let id = profileID ?? currentProfileID
        return id == "default" ? key : "profile." + id + "." + key
    }
    func addProfile(_ name: String) throws -> String {
        guard profilesReady, !busy else { throw ProfileRegistryError(message: "処理が終わってからもう一度選んでください。") }
        busy = true
        defer { busy = false }
        profileRegistry = try profileStore.adding(name, to: profileRegistry)
        return profileRegistry.profiles.last!.id
    }
    func renameProfile(_ profile: StudyProfile, name: String) throws {
        guard profilesReady, !busy else { throw ProfileRegistryError(message: "処理が終わってからもう一度選んでください。") }
        busy = true
        defer { busy = false }
        profileRegistry = try profileStore.renaming(profile.id, to: name, in: profileRegistry)
    }
    func switchProfile(_ id: String) async throws {
        guard profilesReady, !busy else { throw ProfileRegistryError(message: "処理が終わってからもう一度選んでください。") }
        guard id != currentProfileID else { showingProfiles = false; return }
        guard profileRegistry.profiles.contains(where: { $0.id == id }) else { throw ProfileRegistryError(message: "プロファイルが見つかりません。") }
        busy = true
        defer { busy = false }
        leave() // Stops media/callbacks; its refresh is suppressed by the busy gate.
        typedAnswer = ""; answerOverride = nil; revealed = false; finished = false; timedReminder = false
        let previous = engine
        let replacement = Engine(root: try profileStore.root(for: id))
        do {
            let nextDecks = try await replacement.decks()
            let nextAccount = try AccountStore.load(profileID: id)
            try await previous.close()
            let nextRegistry: ProfileRegistry
            do { nextRegistry = try profileStore.selecting(id, in: profileRegistry) }
            catch { _ = try? await previous.decks(); throw error }
            engine = replacement
            profileRegistry = nextRegistry
            decks = nextDecks
            account = nextAccount
            lastSync = UserDefaults.standard.object(forKey: profilePreferenceKey("lastSync")) as? Date
            browserSearch = ""; syncStatus = ""; syncDecision = nil; chooseFullSync = false; confirmDirection = nil
            pendingCollectionImport = nil; cardAPIDenials = 0
            showingProfiles = false
        } catch {
            try? await replacement.close()
            throw error
        }
    }
    func deleteProfile(_ profile: StudyProfile) throws {
        guard profilesReady, !busy, profile.id != currentProfileID,
              profileRegistry.profiles.contains(where: { $0.id == profile.id }) else { throw ProfileRegistryError(message: "使用中のプロファイルは削除できません。") }
        busy = true
        defer { busy = false }
        let credentials = try AccountStore.load(profileID: profile.id)
        try AccountStore.delete(profileID: profile.id)
        do { profileRegistry = try profileStore.deletingInactive(profile.id, in: profileRegistry) }
        catch { if let credentials { try? AccountStore.save(credentials, profileID: profile.id) }; throw error }
        ReviewReminderStore.delete(profileID: profile.id)
        for key in ["lastSync", "lastBrowserSearch", "allowCollectionCardAPI"] {
            UserDefaults.standard.removeObject(forKey: profilePreferenceKey(key, profileID: profile.id))
        }
    }
}
