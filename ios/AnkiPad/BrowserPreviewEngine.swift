import Foundation

extension Engine {
    func browserPreview(rowIDs: [String], selected: [String], notesMode: Bool) throws -> CardPreviewRequest {
        try CardPreviewRequest.browser(rowIDs: rowIDs, selected: selected, notesMode: notesMode) { note in
            try call("NotesService.CardsOfNote", ["nid": note])["cids"] as? [String] ?? []
        }
    }
}
