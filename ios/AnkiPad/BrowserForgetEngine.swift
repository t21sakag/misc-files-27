import Foundation

extension Engine {
    /// Validate every target before the first mutation. The backend otherwise
    /// ignores missing IDs and can reset only part of a stale selection.
    /// This synchronous actor turn prevents another engine call interleaving
    /// target validation, the required backup, and the scheduling operation.
    func forgetBrowserCards(_ cardIDs: [String], options: BrowserForgetOptions) throws {
        let arguments = try options.arguments(cardIDs: cardIDs)
        for id in cardIDs { _ = try call("CardsService.GetCard", ["cid": id]) }
        try backup()
        _ = try call("SchedulerService.ScheduleCardsAsNew", arguments)
    }
}
