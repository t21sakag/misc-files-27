import Foundation

@main
struct TagSelectionSmoke {
    static func main() {
        // 1. Hierarchy & normalization parity with TagsUtil / TagsDialog.addTagFilter
        assert(TagSelectionHierarchy.parts(of: "a::b::c") == ["a", "b", "c"])
        assert(TagSelectionHierarchy.parts(of: "a::::c") == ["a", "blank", "c"])
        assert(TagSelectionHierarchy.uniformedTag("a::b::") == "a::b")
        assert(TagSelectionHierarchy.uniformedTag("a::::b") == "a::blank::b")
        assert(TagSelectionHierarchy.ancestors(of: "a::b::c") == ["a", "a::b"])
        assert(TagSelectionHierarchy.normalizeEnteredTag("  science math ") == "science::math")
        assert(TagSelectionHierarchy.normalizeEnteredTag("science: math") == "science::math")
        assert(TagSelectionHierarchy.normalizeEnteredTag("science:: math") == "science::math")
        assert(TagSelectionHierarchy.normalizeEnteredTag("   ") == nil)
        assert(TagSelectionHierarchy.normalizeEnteredTag("::") == nil)

        // 2. Case-insensitive set preserves first casing
        var set = CaseInsensitiveTagSet(["Vocab", "vocab", "Grammar"])
        assert(set.elements == ["Vocab", "Grammar"])
        assert(set.contains("VOCAB"))
        assert(!set.insert("vOcAb"))

        // 3. Single-note / NoteEditor mode with unsaved extra tags & hierarchy ancestors
        var editorState = TagSelectionState(
            dialogType: .editTags,
            allTags: [" z_root::leaf ", "alpha::sub::item"].map { $0.trimmingCharacters(in: .whitespaces) },
            checkedTags: [],
            extraCheckedTags: ["alpha::sub::item", "draft_only"]
        )
        assert(editorState.isChecked("ALPHA::SUB::ITEM"))
        assert(editorState.isChecked("draft_only"))
        // Ancestors "alpha" and "alpha::sub" are display-indeterminate, NOT partiallySelected
        assert(editorState.isIndeterminate("alpha"))
        assert(editorState.isIndeterminate("alpha::sub"))
        assert(editorState.partiallySelectedTagList.isEmpty)

        // 4. Priority root sorting & hierarchical case-insensitive DFN comparison
        // "alpha" and "draft_only" have active tags, so they sort before inactive "z_root"
        assert(editorState.allTagList == ["alpha", "alpha::sub", "alpha::sub::item", "draft_only", "z_root", "z_root::leaf"])

        // 5. Parent checkbox state depends on full tree even when search filters out a sibling
        _ = editorState.addTag("alpha::sub::sibling")
        // sibling is added as checked; uncheck sibling so alpha::sub has 1 checked + 1 unchecked child
        _ = editorState.uncheck("alpha::sub::sibling", uncheckChildren: false)
        _ = editorState.check("alpha::sub", checkChildren: false)
        editorState.searchQuery = "item"
        let filteredRows = editorState.visibleRows()
        assert(filteredRows.map(\.tag) == ["alpha", "alpha::sub", "alpha::sub::item"])
        // Even though "alpha::sub::sibling" is hidden by search, "alpha::sub" has an unchecked descendant in the full tree,
        // so its display state is .indeterminate, not .checked!
        let subRow = filteredRows.first { $0.tag == "alpha::sub" }!
        assert(subRow.checkState == .indeterminate)

        // 6. Toggling parent row does not overwrite children
        editorState.searchQuery = ""
        editorState.toggleRow("alpha::sub") // was checked -> becomes unchecked
        assert(!editorState.isChecked("alpha::sub"))
        assert(editorState.isChecked("alpha::sub::item"))
        assert(!editorState.isChecked("alpha::sub::sibling"))

        // 7. toggleAllCheckedStatuses acts on ALL tags (including hidden/filtered & ancestors)
        editorState.searchQuery = "z_root"
        let selectedAll = editorState.toggleAllCheckedStatuses()
        assert(selectedAll == true)
        assert(editorState.checkedTagList.count == editorState.allTagList.count)
        assert(editorState.indeterminateTags.isEmpty)
        assert(editorState.partiallySelectedTagList.isEmpty)
        let clearedAll = editorState.toggleAllCheckedStatuses()
        assert(clearedAll == false)
        assert(editorState.checkedTagList.isEmpty)

        // 8. Multi-note tri-state mode preserves per-note partial tags without unioning
        let multiState = TagSelectionState(
            dialogType: .editTags,
            allTags: ["common", "partial::child1", "partial::child2", "unselected"],
            checkedTags: ["common", "partial::child1"],
            uncheckedTags: ["partial::child1", "partial::child2", "unselected"]
        )
        assert(multiState.checkedTagList == ["common"])
        assert(multiState.partiallySelectedTagList == ["partial::child1"])
        // Ancestor "partial" is display-indeterminate, but NOT in partiallySelectedTagList
        assert(multiState.isIndeterminate("partial"))
        assert(!multiState.isPartiallySelected("partial"))

        // Note 1 had ["common", "partial::child1"], Note 2 had ["common"]
        assert(multiState.updatedNoteTags(previous: ["common", "partial::child1"]) == ["common", "partial::child1"])
        assert(multiState.updatedNoteTags(previous: ["common"]) == ["common"])

        // 9. Non-edit dialog types forbid adding new tags
        var filterState = TagSelectionState(
            dialogType: .filterByTag,
            allTags: ["existing"],
            checkedTags: []
        )
        assert(filterState.addTag("new_tag") == nil)
        assert(filterState.allTagList == ["existing"])

        print("PASS: TagSelectionState hierarchy, case-insensitivity, parent tri-state, full-set toggleAll, and partial preservation")
    }
}
