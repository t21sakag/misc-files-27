import Foundation

/// Collection-owned names use the same flagLabels object as AnkiDroid.
/// Names affect presentation only; card values and search codes stay 0...7.
struct FlagLabels: Equatable {
    private(set) var custom: [String: String] = [:]
    init(_ object: Any? = nil) {
        guard let values = object as? [String: Any] else { return }
        for code in 1...7 {
            guard let value = values[String(code)], !(value is NSNull) else { continue }
            if let text = value as? String { custom[String(code)] = text }
            else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                    let text = String(data: data, encoding: .utf8) { custom[String(code)] = text }
        }
    }
    func name(_ code: Int) -> String {
        if (1...7).contains(code), let value = custom[String(code)] { return value }
        switch code {
        case 1: return AppText.localized("赤")
        case 2: return AppText.localized("オレンジ")
        case 3: return AppText.localized("緑")
        case 4: return AppText.localized("青")
        case 5: return AppText.localized("ピンク")
        case 6: return AppText.localized("ターコイズ")
        case 7: return AppText.localized("紫")
        default: return AppText.localized("なし")
        }
    }
}
