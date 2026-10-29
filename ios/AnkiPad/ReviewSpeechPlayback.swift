import SwiftUI
import AVFoundation

struct ReviewSpeechRequest: Identifiable {
    let id = UUID()
    let profileID: String
    let cardKey: String
    let context: ReviewSpeechContext
    let voices: [InstalledSpeechVoice]
    let manual: Bool
}

extension StudyModel {
    var installedSpeechVoices: [InstalledSpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            speechVoiceCache[voice.identifier] = voice
            return InstalledSpeechVoice(id: voice.identifier, name: voice.name, language: voice.language)
        }
    }
    func cancelSpeechPlayback(stopAudio: Bool = true) {
        speechGeneration = UUID()
        speechTask?.cancel(); speechTask = nil
        voiceContextTask?.cancel(); voiceContextTask = nil
        speechPreparing = false; speechRequest = nil
        speechResume = nil; speechChoiceApplied = false
        if stopAudio { audio.stop() }
    }
    func prepareVoiceSpeechContexts() {
        guard showingReviewVoice, let card, ReviewSpeechPreferences.enabled(profileID: currentProfileID) else { return }
        voiceContextTask?.cancel()
        let profile = currentProfileID, engine = self.engine
        voiceContextTask = Task {
            for side in [ReviewSpeechScope.Side.question, .answer] where speechContexts[side] == nil {
                do {
                    let context = try await engine.reviewSpeechContext(card: card, side: side)
                    guard !Task.isCancelled, showingReviewVoice, self.card?.mutationKey == card.mutationKey, currentProfileID == profile else { return }
                    speechContexts[side] = context
                } catch { return }
            }
        }
    }
    private func speechStillCurrent(_ card: StudyCard, profile: String, generation: UUID) -> Bool {
        !Task.isCancelled && speechGeneration == generation && currentProfileID == profile
            && self.card?.mutationKey == card.mutationKey && reviewSceneActive
    }
    func playReviewSides(_ sides: [ReviewSpeechScope.Side], append: Bool = false, completion: (() -> Void)? = nil) {
        guard let card, reviewSceneActive else { return }
        cancelSpeechPlayback(stopAudio: !append)
        let legacy = ReviewSpeechPreferences.enabled(profileID: currentProfileID)
        let currentTags = revealed ? card.answerAV : card.questionAV
        if !legacy || !currentTags.isEmpty {
            let tags = sides.flatMap { $0 == .question ? card.questionAV : card.answerAV }
            if append { audio.append(tags, media: engine.media) }
            else { audio.play(tags, media: engine.media, voices: speechVoiceCache, completion: completion) }
            return
        }
        let generation = speechGeneration
        let face = revealed
        let profile = currentProfileID
        let engine = self.engine
        speechPreparing = true
        speechTask = Task {
            defer { if speechGeneration == generation { speechPreparing = false; speechTask = nil } }
            do {
                var tags: [[String: Any]] = []
                let voices = installedSpeechVoices
                for side in sides {
                    let nativeTags = side == .question ? card.questionAV : card.answerAV
                    if !nativeTags.isEmpty { tags += nativeTags; continue }
                    let context = try await engine.reviewSpeechContext(card: card, side: side)
                    guard speechStillCurrent(card, profile: profile, generation: generation) else { return }
                    speechContexts[side] = context
                    let choice = ReviewSpeechPreferences.load(profileID: profile, scope: context.scope)
                    switch ReviewSpeechPlan.prepare(context.snippets, choice: choice, voices: voices) {
                    case .needsChoice:
                        audio.stop()
                        speechResume = { [weak self] in
                            guard let self, self.revealed == face else { return }
                            self.playReviewSides(sides, append: false, completion: completion)
                        }
                        speechRequest = ReviewSpeechRequest(profileID: profile, cardKey: card.mutationKey, context: context, voices: voices, manual: false)
                        return
                    case .ready(let snippets): tags += snippets.map(\.avTag)
                    }
                }
                guard speechStillCurrent(card, profile: profile, generation: generation) else { return }
                guard !tags.isEmpty else { return }
                if append { audio.append(tags, media: engine.media) }
                else { audio.play(tags, media: engine.media, voices: speechVoiceCache, completion: completion) }
            } catch {
                if speechStillCurrent(card, profile: profile, generation: generation) { self.error = error.localizedDescription }
            }
        }
    }
    func openSpeechVoicePicker() {
        guard let card, !busy, reviewSceneActive else { return }
        cancelSpeechPlayback()
        cardSpeech.stop(); cardRecognition.cancel()
        let generation = speechGeneration, profile = currentProfileID
        let side: ReviewSpeechScope.Side = revealed ? .answer : .question
        let engine = self.engine
        speechPreparing = true
        speechTask = Task {
            defer { if speechGeneration == generation { speechPreparing = false; speechTask = nil } }
            do {
                let context = try await engine.reviewSpeechContext(card: card, side: side)
                guard speechStillCurrent(card, profile: profile, generation: generation) else { return }
                speechContexts[side] = context
                speechRequest = ReviewSpeechRequest(profileID: profile, cardKey: card.mutationKey, context: context, voices: installedSpeechVoices, manual: true)
            } catch {
                if speechStillCurrent(card, profile: profile, generation: generation) { self.error = error.localizedDescription }
            }
        }
    }
    private func checkSpeechRequest(_ request: ReviewSpeechRequest) throws {
        guard reviewSceneActive, request.profileID == currentProfileID, card?.mutationKey == request.cardKey,
              speechRequest?.id == request.id else { throw EngineError(message: AppText.localized("学習対象が変わりました。音声を選び直してください。")) }
    }
    func previewSpeechChoice(_ request: ReviewSpeechRequest, choice: ReviewSpeechChoice) throws {
        try checkSpeechRequest(request)
        audio.stop(); cardSpeech.stop(); cardRecognition.cancel(); reviewVoice.finish()
        guard choice.mode != .off else { return }
        let voice = choice.mode == .voice ? choice.voiceID.flatMap { speechVoiceCache[$0] ?? AVSpeechSynthesisVoice(identifier: $0) } : nil
        if choice.mode == .voice && voice == nil { throw EngineError(message: AppText.localized("この音声は現在利用できません。別の音声を選んでください。")) }
        let text = request.context.plainText
        guard !text.isEmpty else { return }
        let snippet = ResolvedSpeechSnippet(text: text, language: voice?.language ?? "", voiceID: voice?.identifier)
        audio.play([snippet.avTag], media: engine.media, voices: speechVoiceCache)
    }
    func applySpeechChoice(_ request: ReviewSpeechRequest, choice: ReviewSpeechChoice) throws {
        try checkSpeechRequest(request)
        if choice.mode == .voice && !request.voices.contains(where: { $0.id == choice.voiceID }) {
            throw EngineError(message: AppText.localized("この音声は現在利用できません。別の音声を選んでください。"))
        }
        try ReviewSpeechPreferences.save(choice, profileID: request.profileID, scope: request.context.scope)
        audio.stop()
        if request.manual {
            let key = request.cardKey, profile = request.profileID
            speechResume = { [weak self] in
                guard let self, self.card?.mutationKey == key, self.currentProfileID == profile, self.reviewSceneActive,
                      choice.mode != .off else { return }
                let voice = choice.voiceID.flatMap { self.speechVoiceCache[$0] ?? AVSpeechSynthesisVoice(identifier: $0) }
                let snippet = ResolvedSpeechSnippet(text: request.context.plainText, language: voice?.language ?? "", voiceID: voice?.identifier)
                self.audio.play([snippet.avTag], media: self.engine.media, voices: self.speechVoiceCache)
            }
        }
        speechChoiceApplied = true
        speechRequest = nil
    }
    func finishSpeechChoice() {
        audio.stop()
        guard speechRequest == nil else { return }
        let resume = speechChoiceApplied ? speechResume : nil
        speechResume = nil; speechChoiceApplied = false; speechRequest = nil
        resume?()
    }
    func speechRequestBinding(inVoice: Bool) -> Binding<ReviewSpeechRequest?> {
        Binding(get: {
            guard !self.busy, !self.nonSpeechPresentationBlocked, self.showingReviewVoice == inVoice else { return nil }
            return self.speechRequest
        }, set: { if $0 == nil { self.speechRequest = nil } })
    }
}
