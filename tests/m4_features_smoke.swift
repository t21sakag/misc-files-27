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
        precondition(CustomSyncCertificateStore.pem(defaults) == nil)

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

        let sampleDERBase64 = "MIIBgjCCASmgAwIBAgIUSkVmeR7RTrMrrqvNCI8quStuDUEwCgYIKoZIzj0EAwIwFzEVMBMGA1UEAwwMdGVzdC5pbnZhbGlkMB4XDTI2MTEyMjE0MzUxOVoXDTI2MTIyMjE0MzUxOVowFzEVMBMGA1UEAwwMdGVzdC5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEUTvEa2T5E4usBF6q5XYOkvkgjPpHJ+4vYX30vzrWQyFkV8oVlpyUZgGDI/z/+6YX1Z5nQHI0X8HCoGrCX/yQIqNTMFEwHQYDVR0OBBYEFFmkZCl7eSe5nlB/hKyFGNfpdGQQMB8GA1UdIwQYMBaAFFmkZCl7eSe5nlB/hKyFGNfpdGQQMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDRwAwRAIgfKMbHnVtCCEKdbNrbFrBlliKIuXAMsjh0if+CMr0OUQCIF72puUVhGgQIME/wJcjjyB4K1V/r/HV1R6Xp6ae3X2P"
        let sampleDER = Data(base64Encoded: sampleDERBase64)!
        let pem = "-----BEGIN CERTIFICATE-----\n\(sampleDER.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]))\n-----END CERTIFICATE-----\n"

        var rejectedReversedMarkers = false
        do {
            let reversed = "-----END CERTIFICATE-----\n\(sampleDER.base64EncodedString())\n-----BEGIN CERTIFICATE-----"
            _ = try CustomSyncCertificateStore.save(Data(reversed.utf8), defaults: defaults)
        } catch {
            rejectedReversedMarkers = true
        }
        precondition(rejectedReversedMarkers)

        var rejectedMultiplePEM = false
        do {
            let multi = pem + "\n" + pem
            _ = try CustomSyncCertificateStore.save(Data(multi.utf8), defaults: defaults)
        } catch {
            rejectedMultiplePEM = true
        }
        precondition(rejectedMultiplePEM)
        precondition(CustomSyncCertificateStore.summary(defaults) == nil)

        let savedFromPEM = try! CustomSyncCertificateStore.save(Data(pem.utf8), defaults: defaults)
        precondition(!savedFromPEM.isEmpty)
        precondition(CustomSyncCertificateStore.summary(defaults)?.contains("\(sampleDER.count) bytes") == true)
        let roundTripPEM = CustomSyncCertificateStore.pem(defaults)
        precondition(roundTripPEM == pem)

        CustomSyncCertificateStore.clear(defaults)
        precondition(CustomSyncCertificateStore.summary(defaults) == nil)
        precondition(CustomSyncCertificateStore.pem(defaults) == nil)

        let savedFromDER = try! CustomSyncCertificateStore.save(sampleDER, defaults: defaults)
        precondition(!savedFromDER.isEmpty)
        precondition(CustomSyncCertificateStore.summary(defaults)?.contains("\(sampleDER.count) bytes") == true)
        precondition(CustomSyncCertificateStore.pem(defaults) == pem)

        CustomSyncCertificateStore.clear(defaults)
        precondition(CustomSyncCertificateStore.summary(defaults) == nil)

        precondition(NoteFieldNewlineCoding.fromHTML("Line 1<br>Line 2<BR/>Line 3<br />Line 4", replaceNewlines: true) == "Line 1\nLine 2\nLine 3\nLine 4")
        precondition(NoteFieldNewlineCoding.fromHTML("Line 1<br>Line 2", replaceNewlines: false) == "Line 1<br>Line 2")
        precondition(NoteFieldNewlineCoding.toHTML("Line 1\nLine 2\r\nLine 3", replaceNewlines: true) == "Line 1<br>Line 2<br>Line 3")
        precondition(NoteFieldNewlineCoding.toHTML("Line 1\nLine 2\r\nLine 3", replaceNewlines: false) == "Line 1\nLine 2\r\nLine 3")

        precondition(ExternalAPIPreferences.isEnabled(defaults) == true)
        ExternalAPIPreferences.setEnabled(false, defaults: defaults)
        precondition(ExternalAPIPreferences.isEnabled(defaults) == false)
        ExternalAPIPreferences.setEnabled(true, defaults: defaults)
        precondition(ExternalAPIPreferences.isEnabled(defaults) == true)

        print("PASS: ReviewerFrameStyle, ReviewerToolbarPosition, CustomSyncCertificateStore, NoteFieldNewlineCoding, ExternalAPIPreferences")
    }
}
