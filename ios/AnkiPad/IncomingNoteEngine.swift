import Foundation

extension Engine {
    /// Avoid special mask fields when a normal text/image note is requested.
    /// Only reads note types and new-note defaults; the editor performs saving.
    func incomingNoteDocument(_ request: EditorRequest) throws -> NoteDocument {
        let current = try noteDocument(cardID: request.cardID, noteID: request.noteID,
                                       typeID: request.copiedDocument?.typeID, deckID: request.deckID)
        guard request.isNew, request.initialDraft != nil || request.incomingMedia != nil else { return current }
        let minimumFields = request.initialDraft?.requiredFieldCount ?? 1
        func suitable(_ document: NoteDocument) -> Bool {
            guard document.fields.count >= minimumFields else { return false }
            return (try? call("ImageOcclusionService.GetImageOcclusionFields", ["notetypeId": document.typeID]))?["fields"] == nil
        }
        if suitable(current) { return current }
        for type in try noteTypes() where type.id != current.typeID {
            let candidate = try noteDocument(cardID: nil, typeID: type.id, deckID: request.deckID)
            if suitable(candidate) { return candidate }
        }
        throw EngineError(message: AppText.localized("受け取った内容に使えるノートタイプがありません。通常のノートタイプを追加してください。"))
    }
}
