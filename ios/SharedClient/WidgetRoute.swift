import Foundation

/// Deck numbers are unique within a collection, never across profiles.
struct WidgetDeckReference: Equatable {
    let profileID: String
    let deckID: String
    var identifier: String { profileID + ":" + deckID }
    init(profileID: String, deckID: String) { self.profileID = profileID; self.deckID = deckID }
    init?(identifier: String) {
        let fields = identifier.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2, WidgetRoute.validProfileID(String(fields[0])), WidgetRoute.validDeckID(String(fields[1])) else { return nil }
        profileID = String(fields[0]); deckID = String(fields[1])
    }
}

/// A route only opens app UI. It never adds, answers, deletes, or syncs data.
struct WidgetRoute: Equatable {
    enum Destination: String { case home, review, options, add }
    let profileID: String
    let deckID: String?
    let destination: Destination

    static func validProfileID(_ value: String) -> Bool {
        value == "default" || UUID(uuidString: value)?.uuidString == value
    }
    static func validDeckID(_ value: String) -> Bool {
        guard let number = Int64(value), number > 0 else { return false }
        return String(number) == value
    }
    init(profileID: String, deckID: String? = nil, destination: Destination) {
        self.profileID = profileID; self.deckID = deckID; self.destination = destination
    }
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "studyclient", parts.host == "widget",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let destination = Destination(rawValue: String(parts.path.dropFirst())), parts.path == "/" + destination.rawValue else { return nil }
        let items = parts.queryItems ?? []
        guard items.allSatisfy({ ["profile", "deck"].contains($0.name) && $0.value != nil }),
              Set(items.map(\.name)).count == items.count,
              let profileID = items.first(where: { $0.name == "profile" })?.value,
              Self.validProfileID(profileID) else { return nil }
        let deckID = items.first(where: { $0.name == "deck" })?.value
        guard deckID == nil || Self.validDeckID(deckID!),
              ![Destination.review, .options].contains(destination) || deckID != nil else { return nil }
        self.init(profileID: profileID, deckID: deckID, destination: destination)
    }
    var url: URL {
        var parts = URLComponents()
        parts.scheme = "studyclient"; parts.host = "widget"; parts.path = "/" + destination.rawValue
        parts.queryItems = [URLQueryItem(name: "profile", value: profileID)]
        if let deckID { parts.queryItems?.append(URLQueryItem(name: "deck", value: deckID)) }
        return parts.url!
    }
}
