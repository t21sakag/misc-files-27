import Foundation

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AppText {
    static func localized(_ key: String) -> String { key }
}

@main struct M4FeaturesSmoke {
    static func main() {
        let suiteName = "com.ankidroid.ipad.m4_features_smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        precondition(ReviewerFrameStyle.allCases.map(\.rawValue) == ["none", "card", "box"])
        precondition(ReviewerFrameStyle.card.title == "カード枠")
        precondition(ReviewerToolbarPosition.allCases.map(\.rawValue) == ["top", "bottom", "none"])
        precondition(ReviewerToolbarPosition.bottom.title == "下部")

        precondition(CustomSyncCertificateStore.summary(defaults) == nil)

        var rejectedInvalid = false
        do {
            _ = try CustomSyncCertificateStore.save(Data("not-a-cert".utf8), defaults: defaults)
        } catch {
            rejectedInvalid = true
        }
        precondition(rejectedInvalid)
        precondition(CustomSyncCertificateStore.summary(defaults) == nil)

        var rejectedBrokenPEM = false
        do {
            let broken = "-----BEGIN CERTIFICATE-----\n%%%invalid%%%\n-----END CERTIFICATE-----"
            _ = try CustomSyncCertificateStore.save(Data(broken.utf8), defaults: defaults)
        } catch {
            rejectedBrokenPEM = true
        }
        precondition(rejectedBrokenPEM)

        let sampleDER = Data([0x30, 0x82, 0x01, 0x0A, 0x02, 0x01, 0x01])
        let pem = "-----BEGIN CERTIFICATE-----\n\(sampleDER.base64EncodedString())\n-----END CERTIFICATE-----"
        let savedSubject = try! CustomSyncCertificateStore.save(Data(pem.utf8), defaults: defaults)
        precondition(!savedSubject.isEmpty)
        precondition(CustomSyncCertificateStore.summary(defaults)?.contains("7 bytes") == true)

        CustomSyncCertificateStore.clear(defaults)
        precondition(CustomSyncCertificateStore.summary(defaults) == nil)

        print("PASS: ReviewerFrameStyle, ReviewerToolbarPosition, CustomSyncCertificateStore PEM/DER validation and persistence")
    }
}
