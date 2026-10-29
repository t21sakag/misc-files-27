import Foundation

extension StudyModel {
    func revealFromButton(cardKey: String) {
        guard !busy, !revealed, !reviewingInteractionBlocked, schedulerReady, card?.mutationKey == cardKey,
              acceptReviewButton() else { return }
        reveal()
    }
    func answerFromButton(_ rating: Int, cardKey: String) {
        guard !busy, revealed, (0...3).contains(rating), !reviewingInteractionBlocked, schedulerReady,
              card?.mutationKey == cardKey, acceptReviewButton() else { return }
        answer(rating)
    }
    private func acceptReviewButton() -> Bool {
        let interval = UserDefaults.standard.object(forKey: "doubleTapTimeout") as? Int ?? 200
        return reviewButtonTiming.accept(now: ProcessInfo.processInfo.systemUptime, intervalMilliseconds: interval)
    }
}
