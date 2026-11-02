import Foundation

@main struct CardRecognitionSessionSmoke {
    static func main() {
        var session = CardRecognitionSession()
        // Each asynchronous boundary can receive stop before its reply.
        for _ in ["speech authorization", "microphone authorization", "audio lease setup"] {
            let permissionReply = session.begin()
            precondition(session.canStart(permissionReply))
            session.stopInput()
            precondition(!session.canStart(permissionReply))
            precondition(!session.didStart(permissionReply))
            precondition(!session.isCurrent(permissionReply))
        }
        let active = session.begin()
        precondition(session.didStart(active))
        precondition(!session.canStart(active))
        session.stopInput(); session.stopInput()
        precondition(session.isCurrent(active), "Stop must retain the final result callback")
        let replacement = session.begin()
        precondition(!session.isCurrent(active), "Old final results must not reach a replacement")
        precondition(session.didStart(replacement))
        session.cancel(); session.stopInput()
        precondition(!session.isCurrent(replacement))
        let pending = session.begin()
        session.cancel()
        precondition(!session.didStart(pending))
        print("PASS: stop at each preparation boundary prevents late capture; listening stop retains final results; replacement/cancel reject stale callbacks")
    }
}
