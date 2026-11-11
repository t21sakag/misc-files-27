import Foundation

extension Engine {
    /// Loads the complete collection tag vocabulary and optional per-note tag state in one actor turn.
    func loadTagSelectionState(noteIDs: [String] = [],
                               extraCheckedTags: [String] = [],
                               dialogType: TagSelectionDialogType = .editTags) throws -> TagSelectionState {
        let allTags = (try call("TagsService.AllTags")["vals"] as? [String] ?? [])
            .map(TagSelectionHierarchy.uniformedTag)
        guard !noteIDs.isEmpty else {
            return TagSelectionState(
                dialogType: dialogType,
                allTags: allTags,
                checkedTags: [],
                uncheckedTags: nil,
                extraCheckedTags: extraCheckedTags
            )
        }
        var noteTagLists: [[String]] = []
        var unionNoteTags = CaseInsensitiveTagSet()
        for rawID in noteIDs {
            guard let parsed = Int64(rawID), parsed > 0 else {
                throw EngineError(message: AppText.localized("変更対象のノートが一致しません。"))
            }
            let note = try call("NotesService.GetNote", ["nid": rawID])
            guard let returnedID = note["id"] as? String, returnedID == rawID,
                  let tags = note["tags"] as? [String] else {
                throw EngineError(message: AppText.localized("変更対象のノートが一致しません。"))
            }
            let normalized = tags.map(TagSelectionHierarchy.uniformedTag)
            noteTagLists.append(normalized)
            unionNoteTags.formUnion(normalized)
        }
        var universe = CaseInsensitiveTagSet(allTags)
        universe.formUnion(unionNoteTags.elements)
        var unchecked = CaseInsensitiveTagSet()
        for tagsOnNote in noteTagLists {
            let noteSet = CaseInsensitiveTagSet(tagsOnNote)
            for candidate in universe.elements where !noteSet.contains(candidate) {
                _ = unchecked.insert(candidate)
            }
        }
        return TagSelectionState(
            dialogType: dialogType,
            allTags: universe.elements,
            checkedTags: unionNoteTags.elements,
            uncheckedTags: unchecked.elements,
            extraCheckedTags: extraCheckedTags
        )
    }

    /// Validates all target notes before writing and updates their tags atomically in a single UpdateNotes call.
    func applyBatchTagSelection(noteIDs: [String],
                                checkedTags: [String],
                                partiallySelectedTags: [String]) throws {
        guard !noteIDs.isEmpty else {
            throw EngineError(message: AppText.localized("変更対象のノートが一致しません。"))
        }
        var seenIDs: Set<String> = []
        var updatedNotes: [[String: Any]] = []
        for rawID in noteIDs {
            guard let parsed = Int64(rawID), parsed > 0, seenIDs.insert(rawID).inserted else {
                throw EngineError(message: AppText.localized("変更対象のノートが一致しません。"))
            }
            var note = try call("NotesService.GetNote", ["nid": rawID])
            guard let returnedID = note["id"] as? String, returnedID == rawID,
                  let previousTags = note["tags"] as? [String] else {
                throw EngineError(message: AppText.localized("変更対象のノートが一致しません。"))
            }
            note["tags"] = TagSelectionHierarchy.updatedTags(
                previous: previousTags.map(TagSelectionHierarchy.uniformedTag),
                selected: checkedTags,
                indeterminate: partiallySelectedTags
            )
            updatedNotes.append(note)
        }
        _ = try call("NotesService.UpdateNotes", ["notes": updatedNotes])
    }
}
