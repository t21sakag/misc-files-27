import Foundation

struct ReviewOptions {
    let showCounts: Bool
    let showIntervals: Bool
    let hideAudioButtons: Bool
    let interruptAudio: Bool
    let autoplay: Bool
    let replayQuestion: Bool
    let capMilliseconds: Int
    let showTimer: Bool
    let stopTimerOnAnswer: Bool
    let questionSeconds: Double
    let answerSeconds: Double
    let questionAction: String
    let answerAction: String
    let waitForAudio: Bool
}
extension Engine {
    func reviewOptions(card: [String: Any]) throws -> ReviewOptions {
        let preferences = try call("ConfigService.GetPreferences")
        let reviewing = preferences["reviewing"] as? [String: Any] ?? [:]
        let deck = try call("DecksService.GetDeck", ["did": card["originalDeckId"] as? String ?? card["deckId"] as? String ?? "1"])
        let normal = deck["normal"] as? [String: Any] ?? [:]
        let config = try call("DeckConfigService.GetDeckConfig", ["dcid": normal["configId"] as? String ?? "1"])["config"] as? [String: Any] ?? [:]
        let cap = config["capAnswerTimeToSecs"] as? Int ?? 0
        return ReviewOptions(showCounts: reviewing["showRemainingDueCounts"] as? Bool ?? false,
            showIntervals: reviewing["showIntervalsOnButtons"] as? Bool ?? false,
            hideAudioButtons: reviewing["hideAudioPlayButtons"] as? Bool ?? false,
            interruptAudio: reviewing["interruptAudioWhenAnswering"] as? Bool ?? false,
            autoplay: !(config["disableAutoplay"] as? Bool ?? false),
            replayQuestion: !(config["skipQuestionWhenReplayingAnswer"] as? Bool ?? false),
            capMilliseconds: cap > 0 ? cap * 1000 : Int(UInt32.max),
            showTimer: config["showTimer"] as? Bool ?? false,
            stopTimerOnAnswer: config["stopTimerOnAnswer"] as? Bool ?? false,
            questionSeconds: config["secondsToShowQuestion"] as? Double ?? 0,
            answerSeconds: config["secondsToShowAnswer"] as? Double ?? 0,
            questionAction: config["questionAction"] as? String ?? "QUESTION_ACTION_SHOW_ANSWER",
            answerAction: config["answerAction"] as? String ?? "ANSWER_ACTION_BURY_CARD",
            waitForAudio: config["waitForAudio"] as? Bool ?? false)
    }
}
