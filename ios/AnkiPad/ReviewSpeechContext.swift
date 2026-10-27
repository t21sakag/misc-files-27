import Foundation

struct ReviewSpeechContext {
    let scope: ReviewSpeechScope
    let snippets: [SpeechSnippet]
    let plainText: String
}
extension Engine {
    func reviewSpeechContext(card: StudyCard, side: ReviewSpeechScope.Side) throws -> ReviewSpeechContext {
        let stored = try call("CardsService.GetCard", ["cid": card.id])
        let note = try call("NotesService.GetNote", ["nid": card.noteID])
        let schema = try call("NotetypesService.GetNotetype", ["ntid": note["notetypeId"] as? String ?? "0"])
        let cloze = (schema["config"] as? [String: Any])?["kind"] as? String == "KIND_CLOZE"
        let scope = ReviewSpeechScope(deckID: stored["deckId"] as? String ?? card.deckID,
            originalDeckID: stored["originalDeckId"] as? String ?? "0", ordinal: card.ordinal, cloze: cloze, side: side)
        let html = side == .question ? card.question : LegacySpeechText.answerOnly(card.answer)
        return ReviewSpeechContext(scope: scope, snippets: try LegacySpeechText.parse(html), plainText: try LegacySpeechText.parse(html, localized: false).map(\.text).joined(separator: " "))
    }
}
