import Foundation

enum TagSelectionDialogType: String, Equatable {
    case editTags
    case filterByTag
    case customStudyTags

    var showsAddButton: Bool { self == .editTags }
    var showsRadioOptions: Bool { self != .editTags }
}

enum TagSelectionCheckState: String, Equatable {
    case unchecked
    case checked
    case indeterminate
}

struct TagSelectionRow: Identifiable, Equatable {
    var id: String { tag.lowercased() }
    let tag: String
    let displayName: String
    let level: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let checkState: TagSelectionCheckState
}

enum TagSelectionHierarchy {
    static func parts(of tag: String) -> [String] {
        tag.components(separatedBy: "::").map { $0.isEmpty ? "blank" : $0 }
    }

    static func ancestors(of tag: String) -> [String] {
        let segments = parts(of: tag)
        guard segments.count > 1 else { return [] }
        return (1..<segments.count).map { segments.prefix($0).joined(separator: "::") }
    }

    static func uniformedTag(_ tag: String) -> String {
        let segments = parts(of: tag)
        if segments.count > 1 && segments.last == "blank" {
            return segments.dropLast().joined(separator: "::")
        }
        return segments.joined(separator: "::")
    }

    /// Mirrors TagsDialog.addTagFilter + getUniformedTag: spaces convert to hierarchy separators.
    static func normalizeEnteredTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var converted = ""
        let chars = Array(trimmed)
        for index in chars.indices {
            let char = chars[index]
            if char == " " {
                let prev1 = index >= 1 ? chars[index - 1] : nil
                let prev2 = index >= 2 ? chars[index - 2] : nil
                if prev1 == ":" && prev2 == ":" {
                    continue
                } else if prev1 == ":" {
                    converted.append(":")
                } else {
                    converted.append("::")
                }
            } else {
                converted.append(char)
            }
        }
        let uniformed = uniformedTag(converted)
        guard !uniformed.isEmpty, uniformed != "blank" else { return nil }
        return uniformed
    }

    static func compareTag(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = parts(of: lhs)
        let rightParts = parts(of: rhs)
        let limit = min(leftParts.count, rightParts.count)
        for idx in 0..<limit {
            let cmp = leftParts[idx].caseInsensitiveCompare(rightParts[idx])
            if cmp != .orderedSame { return cmp }
        }
        if leftParts.count == rightParts.count { return .orderedSame }
        return leftParts.count < rightParts.count ? .orderedAscending : .orderedDescending
    }

    static func updatedTags(previous: [String], selected: [String], indeterminate: [String]) -> [String] {
        var updated = CaseInsensitiveTagSet(selected)
        let partialSet = CaseInsensitiveTagSet(indeterminate)
        for tag in previous where partialSet.contains(tag) {
            _ = updated.insert(tag)
        }
        return updated.elements
    }
}

struct CaseInsensitiveTagSet: Equatable {
    private(set) var elements: [String] = []
    private var indexByLower: [String: Int] = [:]

    init(_ tags: [String] = []) {
        for tag in tags { _ = insert(tag) }
    }

    var count: Int { elements.count }
    var isEmpty: Bool { elements.isEmpty }

    func contains(_ tag: String) -> Bool {
        indexByLower[tag.lowercased()] != nil
    }

    func canonical(_ tag: String) -> String? {
        guard let idx = indexByLower[tag.lowercased()] else { return nil }
        return elements[idx]
    }

    @discardableResult
    mutating func insert(_ tag: String) -> Bool {
        let key = tag.lowercased()
        guard indexByLower[key] == nil else { return false }
        indexByLower[key] = elements.count
        elements.append(tag)
        return true
    }

    @discardableResult
    mutating func remove(_ tag: String) -> Bool {
        let key = tag.lowercased()
        guard let idx = indexByLower.removeValue(forKey: key) else { return false }
        elements.remove(at: idx)
        indexByLower.removeAll(keepingCapacity: true)
        for (offset, item) in elements.enumerated() {
            indexByLower[item.lowercased()] = offset
        }
        return true
    }

    mutating func removeAll() {
        elements.removeAll()
        indexByLower.removeAll()
    }

    mutating func formUnion(_ other: [String]) {
        for tag in other { _ = insert(tag) }
    }

    mutating func sort(by areInIncreasingOrder: (String, String) -> Bool) {
        elements.sort(by: areInIncreasingOrder)
        indexByLower.removeAll(keepingCapacity: true)
        for (offset, item) in elements.enumerated() {
            indexByLower[item.lowercased()] = offset
        }
    }
}

struct TagSelectionState: Equatable {
    let dialogType: TagSelectionDialogType
    private(set) var allTags: CaseInsensitiveTagSet
    private(set) var checkedTags: CaseInsensitiveTagSet
    private(set) var indeterminateTags: CaseInsensitiveTagSet
    private(set) var partiallySelectedTags: CaseInsensitiveTagSet
    var expandedTags: CaseInsensitiveTagSet
    var searchQuery: String = ""
    var matchAllTags: Bool = true

    init(dialogType: TagSelectionDialogType = .editTags,
         allTags: [String],
         checkedTags: [String],
         uncheckedTags: [String]? = nil,
         extraCheckedTags: [String] = []) {
        self.dialogType = dialogType
        self.checkedTags = CaseInsensitiveTagSet(checkedTags)
        self.allTags = CaseInsensitiveTagSet(allTags)
        self.allTags.formUnion(self.checkedTags.elements)
        if let uncheckedTags {
            self.allTags.formUnion(uncheckedTags)
            let uncheckedSet = CaseInsensitiveTagSet(uncheckedTags)
            var overlap: [String] = []
            for tag in self.checkedTags.elements where uncheckedSet.contains(tag) {
                overlap.append(tag)
            }
            self.indeterminateTags = CaseInsensitiveTagSet(overlap)
            for tag in overlap {
                _ = self.checkedTags.remove(tag)
            }
            self.partiallySelectedTags = self.indeterminateTags
        } else {
            self.indeterminateTags = CaseInsensitiveTagSet()
            self.partiallySelectedTags = CaseInsensitiveTagSet()
        }
        for extra in extraCheckedTags {
            let uniformed = TagSelectionHierarchy.uniformedTag(extra)
            _ = self.allTags.insert(uniformed)
            _ = self.checkedTags.insert(uniformed)
            _ = self.indeterminateTags.remove(uniformed)
            _ = self.partiallySelectedTags.remove(uniformed)
        }
        self.expandedTags = CaseInsensitiveTagSet()
        prepareTagHierarchy()
        sort()
        expandAncestorsOfActiveTags()
    }

    var checkedTagList: [String] { checkedTags.elements }
    var partiallySelectedTagList: [String] { partiallySelectedTags.elements }
    var allTagList: [String] { allTags.elements }

    func isChecked(_ tag: String) -> Bool { checkedTags.contains(tag) }
    func isIndeterminate(_ tag: String) -> Bool { indeterminateTags.contains(tag) }
    func isPartiallySelected(_ tag: String) -> Bool { partiallySelectedTags.contains(tag) }

    mutating func toggleRow(_ tag: String) {
        if isChecked(tag) {
            _ = uncheck(tag, uncheckChildren: false)
        } else {
            _ = check(tag, checkChildren: false)
        }
    }

    @discardableResult
    mutating func check(_ tag: String, checkChildren: Bool = true) -> Bool {
        let uniformed = TagSelectionHierarchy.uniformedTag(tag)
        guard allTags.contains(uniformed) else { return false }
        let added = checkedTags.insert(allTags.canonical(uniformed) ?? uniformed)
        let clearedIndeterminate = indeterminateTags.remove(uniformed)
        _ = partiallySelectedTags.remove(uniformed)
        guard added || clearedIndeterminate else { return false }

        if checkChildren {
            let prefix = uniformed.lowercased() + "::"
            for candidate in allTags.elements where candidate.lowercased().hasPrefix(prefix) {
                _ = checkedTags.insert(candidate)
                _ = indeterminateTags.remove(candidate)
                _ = partiallySelectedTags.remove(candidate)
            }
        }
        markAncestorsIndeterminate(of: uniformed)
        return true
    }

    @discardableResult
    mutating func uncheck(_ tag: String, uncheckChildren: Bool = true) -> Bool {
        let uniformed = TagSelectionHierarchy.uniformedTag(tag)
        let removedChecked = checkedTags.remove(uniformed)
        let removedIndeterminate = indeterminateTags.remove(uniformed)
        _ = partiallySelectedTags.remove(uniformed)
        guard removedChecked || removedIndeterminate else { return false }

        if uncheckChildren {
            let prefix = uniformed.lowercased() + "::"
            for candidate in allTags.elements where candidate.lowercased().hasPrefix(prefix) {
                _ = checkedTags.remove(candidate)
                _ = indeterminateTags.remove(candidate)
                _ = partiallySelectedTags.remove(candidate)
            }
        }
        unmarkAncestorsIndeterminateIfNeeded(of: uniformed)
        return true
    }

    @discardableResult
    mutating func addTag(_ rawInput: String) -> String? {
        guard dialogType.showsAddButton,
              let uniformed = TagSelectionHierarchy.normalizeEnteredTag(rawInput) else { return nil }
        _ = allTags.insert(uniformed)
        for ancestor in TagSelectionHierarchy.ancestors(of: uniformed) {
            _ = allTags.insert(ancestor)
            _ = expandedTags.insert(ancestor)
        }
        _ = check(uniformed, checkChildren: false)
        sort()
        return allTags.canonical(uniformed) ?? uniformed
    }

    @discardableResult
    mutating func toggleAllCheckedStatuses() -> Bool {
        indeterminateTags.removeAll()
        partiallySelectedTags.removeAll()
        if allTags.count == checkedTags.count {
            checkedTags.removeAll()
            return false
        }
        checkedTags = allTags
        return true
    }

    mutating func toggleExpanded(_ tag: String) {
        if !expandedTags.insert(tag) {
            _ = expandedTags.remove(tag)
        }
    }

    mutating func sort() {
        var activeRoots = CaseInsensitiveTagSet()
        for tag in checkedTags.elements + indeterminateTags.elements {
            if let root = TagSelectionHierarchy.parts(of: tag).first {
                _ = activeRoots.insert(root)
            }
        }
        allTags.sort { lhs, rhs in
            let leftRoot = TagSelectionHierarchy.parts(of: lhs).first ?? lhs
            let rightRoot = TagSelectionHierarchy.parts(of: rhs).first ?? rhs
            if leftRoot.caseInsensitiveCompare(rightRoot) != .orderedSame {
                let leftActive = activeRoots.contains(leftRoot)
                let rightActive = activeRoots.contains(rightRoot)
                if leftActive != rightActive {
                    return leftActive
                }
            }
            return TagSelectionHierarchy.compareTag(lhs, rhs) == .orderedAscending
        }
    }

    func visibleRows() -> [TagSelectionRow] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let childrenByParent = buildChildrenMap()
        let matchingSet: CaseInsensitiveTagSet? = {
            guard !query.isEmpty else { return nil }
            var matches = CaseInsensitiveTagSet()
            for tag in allTags.elements where tag.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                _ = matches.insert(tag)
                for ancestor in TagSelectionHierarchy.ancestors(of: tag) {
                    _ = matches.insert(ancestor)
                }
            }
            return matches
        }()

        var rows: [TagSelectionRow] = []
        for tag in allTags.elements {
            if let matchingSet {
                guard matchingSet.contains(tag) else { continue }
            } else {
                let ancestors = TagSelectionHierarchy.ancestors(of: tag)
                guard ancestors.allSatisfy({ expandedTags.contains($0) }) else { continue }
            }
            let segments = TagSelectionHierarchy.parts(of: tag)
            let descendants = childrenByParent[tag.lowercased()] ?? []
            let hasChildren = !descendants.isEmpty
            let isExpanded = matchingSet != nil ? true : expandedTags.contains(tag)
            let state = resolvedCheckState(for: tag, descendants: descendants)
            rows.append(TagSelectionRow(
                tag: tag,
                displayName: segments.last ?? tag,
                level: max(0, segments.count - 1),
                hasChildren: hasChildren,
                isExpanded: isExpanded,
                checkState: state
            ))
        }
        return rows
    }

    func updatedNoteTags(previous: [String]) -> [String] {
        TagSelectionHierarchy.updatedTags(
            previous: previous,
            selected: checkedTags.elements,
            indeterminate: partiallySelectedTags.elements
        )
    }

    private func buildChildrenMap() -> [String: [String]] {
        var map: [String: [String]] = [:]
        for tag in allTags.elements {
            for ancestor in TagSelectionHierarchy.ancestors(of: tag) {
                map[ancestor.lowercased(), default: []].append(tag)
            }
        }
        return map
    }

    private func resolvedCheckState(for tag: String, descendants: [String]) -> TagSelectionCheckState {
        guard !descendants.isEmpty else {
            if isChecked(tag) { return .checked }
            if isIndeterminate(tag) { return .indeterminate }
            return .unchecked
        }
        let allSubtagsChecked = descendants.allSatisfy { isChecked($0) }
        let anySubtagsActive = descendants.contains { isChecked($0) || isIndeterminate($0) }
        if isChecked(tag) && allSubtagsChecked {
            return .checked
        }
        if isChecked(tag) || isIndeterminate(tag) || anySubtagsActive {
            return .indeterminate
        }
        return .unchecked
    }

    private mutating func prepareTagHierarchy() {
        var ancestorsToAdd: [String] = []
        for tag in allTags.elements {
            ancestorsToAdd.append(contentsOf: TagSelectionHierarchy.ancestors(of: tag))
        }
        allTags.formUnion(ancestorsToAdd)
        let active = checkedTags.elements + indeterminateTags.elements
        for tag in active {
            markAncestorsIndeterminate(of: tag)
        }
    }

    private mutating func markAncestorsIndeterminate(of tag: String) {
        guard allTags.contains(tag) else { return }
        for ancestor in TagSelectionHierarchy.ancestors(of: tag) where !checkedTags.contains(ancestor) {
            _ = indeterminateTags.insert(allTags.canonical(ancestor) ?? ancestor)
        }
    }

    private mutating func unmarkAncestorsIndeterminateIfNeeded(of tag: String) {
        let active = checkedTags.elements + indeterminateTags.elements
        for ancestor in TagSelectionHierarchy.ancestors(of: tag).reversed() {
            guard !checkedTags.contains(ancestor) else { continue }
            let prefix = ancestor.lowercased() + "::"
            let hasActiveDescendant = active.contains {
                $0.lowercased() != ancestor.lowercased() && $0.lowercased().hasPrefix(prefix)
            }
            if !hasActiveDescendant {
                _ = indeterminateTags.remove(ancestor)
            }
        }
    }

    private mutating func expandAncestorsOfActiveTags() {
        for tag in checkedTags.elements + indeterminateTags.elements {
            for ancestor in TagSelectionHierarchy.ancestors(of: tag) {
                _ = expandedTags.insert(ancestor)
            }
        }
    }
}
