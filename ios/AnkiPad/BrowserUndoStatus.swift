import Foundation

struct BrowserUndoStatus: Equatable, Sendable {
    let undo: String
    let redo: String

    init(_ value: [String: Any] = [:]) {
        undo = value["undo"] as? String ?? ""
        redo = value["redo"] as? String ?? ""
    }
}
extension Engine {
    func browserUndoStatus() throws -> BrowserUndoStatus {
        BrowserUndoStatus(try call("CollectionService.GetUndoStatus"))
    }
}
