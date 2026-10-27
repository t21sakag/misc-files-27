import Foundation

struct ReviewSpeechScope: Codable, Equatable {
    enum Side: String, Codable { case question, answer }
    let deckID: String
    let template: Int
    let side: Side
    var key: String { deckID + ":" + String(template) + ":" + side.rawValue }
    init(deckID: String, originalDeckID: String = "0", ordinal: Int, cloze: Bool, side: Side) {
        self.deckID = originalDeckID == "0" || originalDeckID.isEmpty ? deckID : originalDeckID
        template = cloze ? 0 : ordinal
        self.side = side
    }
}
struct ReviewSpeechChoice: Codable, Equatable {
    enum Mode: String, Codable { case system, voice, off }
    let mode: Mode
    var voiceID: String? = nil
    static let system = Self(mode: .system)
    static let off = Self(mode: .off)
    var valid: Bool { mode != .voice || !(voiceID ?? "").isEmpty }
}
enum ReviewSpeechPreferences {
    private static func key(_ profileID: String) -> String {
        profileID == "default" ? "ttsVoiceChoices" : "profile." + profileID + ".ttsVoiceChoices"
    }
    static func load(profileID: String, scope: ReviewSpeechScope, defaults: UserDefaults = .standard) -> ReviewSpeechChoice? {
        guard let data = defaults.data(forKey: key(profileID)),
              let choices = try? JSONDecoder().decode([String: ReviewSpeechChoice].self, from: data),
              let choice = choices[scope.key], choice.valid else { return nil }
        return choice
    }
    static func save(_ choice: ReviewSpeechChoice, profileID: String, scope: ReviewSpeechScope, defaults: UserDefaults = .standard) throws {
        guard choice.valid else { throw SpeechTextError() }
        var values: [String: ReviewSpeechChoice] = [:]
        if let data = defaults.data(forKey: key(profileID)) { values = (try? JSONDecoder().decode([String: ReviewSpeechChoice].self, from: data)) ?? [:] }
        values[scope.key] = choice
        defaults.set(try JSONEncoder().encode(values), forKey: key(profileID))
    }
    static func remove(profileID: String, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key(profileID)) }
}
