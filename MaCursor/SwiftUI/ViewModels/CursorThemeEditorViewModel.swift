import AppKit
import Combine
import Foundation

class CursorThemeEditorViewModel: ObservableObject {
    let cursorTheme: CursorThemeModel

    @Published var editingName: String
    @Published var editingCreator: String
    @Published var editingVersion: Double
    @Published var editingHiDPI: Bool
    @Published var editingCursors: [CursorModel] {
        didSet { forwardCursorChanges() }
    }

    @Published var selectedCursorId: String?
    @Published var isShowingUnsavedAlert = false

    struct CursorFingerprint: Equatable {
        let identifier: String
        let frameCount: Int
        let frameDuration: Double
        let hotSpot: CGPoint
        let size: CGSize
        let representationRevision: Int
    }

    struct EditorSnapshot: Equatable {
        var name: String = ""
        var creator: String = ""
        var version: Double = 0
        var isHiDPI: Bool = false
        var cursors: [CursorFingerprint] = []
    }

    @Published private var savedBaseline = EditorSnapshot()

    var isDirty: Bool {
        !pendingAdditions.isEmpty
            || !pendingRemovals.isEmpty
            || currentSnapshot() != savedBaseline
    }

    func currentSnapshot() -> EditorSnapshot {
        EditorSnapshot(
            name: editingName,
            creator: editingCreator,
            version: editingVersion,
            isHiDPI: editingHiDPI,
            cursors: editingCursors.map {
                CursorFingerprint(
                    identifier: $0.identifier,
                    frameCount: $0.frameCount,
                    frameDuration: $0.frameDuration,
                    hotSpot: $0.hotSpot,
                    size: $0.size,
                    representationRevision: $0.representationRevision
                )
            }
        )
    }

    func captureBaseline() {
        pendingAdditions.removeAll()
        pendingRemovals.removeAll()
        savedBaseline = currentSnapshot()
    }

    @Published private var pendingAdditions: [MACCursorSwift] = []
    @Published private var pendingRemovals: Set<String> = []
    private var originalMapping: [String: CursorModel] = [:]
    private var cursorForwarders: [AnyCancellable] = []

    private func forwardCursorChanges() {
        cursorForwarders = editingCursors.map { cursor in
            cursor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }

    init(cursorTheme: CursorThemeModel) {
        self.cursorTheme = cursorTheme
        self.editingName = cursorTheme.name
        self.editingCreator = cursorTheme.creator
        self.editingVersion = cursorTheme.version
        self.editingHiDPI = cursorTheme.isHiDPI

        var copies: [CursorModel] = []
        var mapping: [String: CursorModel] = [:]
        for original in cursorTheme.cursors {
            guard let backingCopy = original.backingCursor.copy() as? MACCursorSwift else { continue }
            let copy = CursorModel(from: backingCopy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            copies.append(copy)
            mapping[copy.id] = original
        }
        self.editingCursors = copies
        self.originalMapping = mapping
        self.savedBaseline = EditorSnapshot(
            name: cursorTheme.name,
            creator: cursorTheme.creator,
            version: cursorTheme.version,
            isHiDPI: cursorTheme.isHiDPI,
            cursors: copies.map {
                CursorFingerprint(
                    identifier: $0.identifier,
                    frameCount: $0.frameCount,
                    frameDuration: $0.frameDuration,
                    hotSpot: $0.hotSpot,
                    size: $0.size,
                    representationRevision: $0.representationRevision
                )
            }
        )
        forwardCursorChanges()
    }

    var selectedCursor: CursorModel? {
        guard let id = selectedCursorId else { return nil }
        return editingCursors.first { $0.id == id }
    }

    @Published var hideTahoeCursors: Bool = MACPreferences.hideTahoeCursors

    var visibleEditingCursors: [CursorModel] {
        if hideTahoeCursors {
            return editingCursors.filter {
                !MACConstants.hiddenCursorAliases.contains($0.identifier)
            }
        }
        return editingCursors
    }

    func usedIdentifiers(excluding cursorId: String) -> Set<String> {
        Set(editingCursors.compactMap { $0.id == cursorId ? nil : $0.identifier })
    }

    static func slotOrderViolation(in cursors: [CursorModel]) -> CursorModel? {
        for cursor in cursors {
            guard let reps = cursor.backingCursor.representations as? [String: NSBitmapImageRep] else { continue }
            let widths = reps.compactMap { key, rep -> (scale: Int, width: Int)? in
                guard let scale = Int(key), scale > 0,
                      CursorGeometry.ladder.contains(UInt(scale)),
                      rep.pixelsWide > 0 else { return nil }
                return (scale, rep.pixelsWide)
            }.sorted { $0.scale < $1.scale }
            guard widths.count > 1 else { continue }
            for index in 1..<widths.count where widths[index].width <= widths[index - 1].width {
                return cursor
            }
        }
        return nil
    }

    func save() -> Error? {
        guard isDirty else { return nil }

        if let violating = Self.slotOrderViolation(in: editingCursors) {
            return NSError(
                domain: MACConstants.errorDomain,
                code: MACConstants.ErrorCode.slotOrderConflict.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "Save failed", comment: "New Cursor Theme Failure Title"),
                    NSLocalizedFailureReasonErrorKey: String(
                        format: NSLocalizedString(
                            "“%@” has slot images out of size order (10× > 5× > 2× > 1×). Fix the slots before saving.",
                            comment: "Save blocked: cursor slot pixel sizes out of order"),
                        violating.name)
                ]
            )
        }

        for editingModel in editingCursors {
            editingModel.syncToBacking()

            if let original = originalMapping[editingModel.id] {
                original.identifier = editingModel.identifier
                original.frameCount = editingModel.frameCount
                original.frameDuration = editingModel.frameDuration
                original.hotSpot = editingModel.hotSpot
                original.size = editingModel.size

                if let reps = editingModel.backingCursor.representations as NSDictionary? {
                    original.backingCursor.setValue(reps.mutableCopy(), forKey: "representations")
                }
                original.representationRevision += 1
            }
        }

        for editingModel in editingCursors {
            let backingId = editingModel.backingCursor.identifier
            if backingId == nil || backingId!.isEmpty {
                let uniqueId = "Unassigned.\(UUID().uuidString)"
                editingModel.backingCursor.identifier = uniqueId
                editingModel.identifier = uniqueId
                if let original = originalMapping[editingModel.id] {
                    original.backingCursor.identifier = uniqueId
                    original.identifier = uniqueId
                }
            }
        }

        cursorTheme.name = editingName
        cursorTheme.creator = editingCreator
        cursorTheme.version = editingVersion
        cursorTheme.isHiDPI = editingHiDPI

        var finalCursors: [CursorModel] = []
        for editingModel in editingCursors {
            if let original = originalMapping[editingModel.id] {
                finalCursors.append(original)
            } else {
                finalCursors.append(editingModel)
            }
        }
        cursorTheme.cursors = finalCursors

        for originalId in pendingRemovals {
            if let original = cursorTheme.backingLibrary.cursors.first(where: { $0.identifier == originalId }) {
                cursorTheme.backingLibrary.removeCursor(original)
            }
        }
        pendingRemovals.removeAll()

        for cursor in pendingAdditions {
            cursorTheme.backingLibrary.addCursor(cursor)
        }
        pendingAdditions.removeAll()

        let error = cursorTheme.save()
        if error == nil {
            rebaseAfterSave()
            captureBaseline()

            if cursorTheme.isApplied {
                _ = CursorService.applyTheme(from: cursorTheme.backingLibrary)
            }
        }
        return error
    }

    private func rebaseAfterSave() {
        let selectedIdentifier = selectedCursor?.identifier
        var copies: [CursorModel] = []
        var mapping: [String: CursorModel] = [:]
        for original in cursorTheme.cursors {
            guard let backingCopy = original.backingCursor.copy() as? MACCursorSwift else { continue }
            let copy = CursorModel(from: backingCopy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            copies.append(copy)
            mapping[copy.id] = original
        }
        editingCursors = copies
        originalMapping = mapping
        if let selectedIdentifier {
            selectedCursorId = editingCursors.first { $0.identifier == selectedIdentifier }?.id
        }
    }

    func revertToSaved() {
        pendingAdditions.removeAll()
        pendingRemovals.removeAll()

        var copies: [CursorModel] = []
        var mapping: [String: CursorModel] = [:]
        for original in cursorTheme.cursors {
            guard let backingCopy = original.backingCursor.copy() as? MACCursorSwift else { continue }
            let copy = CursorModel(from: backingCopy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            copies.append(copy)
            mapping[copy.id] = original
        }

        editingName = cursorTheme.name
        editingCreator = cursorTheme.creator
        editingVersion = cursorTheme.version
        editingHiDPI = cursorTheme.isHiDPI
        editingCursors = copies
        originalMapping = mapping

        captureBaseline()
    }

    func addCursor() {
        let newCursor = MACCursorSwift()
        pendingAdditions.append(newCursor)
        let model = CursorModel(from: newCursor, parentIdentifier: cursorTheme.backingLibrary.identifier)
        editingCursors.append(model)
        editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedEmptySlotIdentifier: String? {
        guard let id = selectedCursorId,
              id.hasPrefix(EditThemeSidebarModel.emptyRowPrefix),
              !editingCursors.contains(where: { $0.id == id }) else { return nil }
        return String(id.dropFirst(EditThemeSidebarModel.emptyRowPrefix.count))
    }

    private func importCursor(from sourceURL: URL, identifier: String) -> MACCursorSwift? {
        let url = SlotImageImporter.normalizedFileURL(sourceURL)
        let ext = url.pathExtension.lowercased()
        if ext == "cur" || ext == "ani" {
            guard let imported = try? WindowsCursorImporter.importFile(from: url) else {
                return nil
            }
            imported.identifier = identifier
            return imported
        }
        if SlotImageImporter.isGIF(url) {
            do {
                if let animated = try SlotImageImporter.importAnimatedGIF(from: url) {
                    return importAnimatedCursor(animated, identifier: identifier)
                }
            } catch {
                return nil
            }
        }
        guard let image = NSImage(contentsOf: url),
              let rep = image.representations.first as? NSBitmapImageRep else {
            return nil
        }
        let scaleValue = SlotImageImporter.inferredScaleValue(forPixelWidth: rep.pixelsWide)
        guard let scale = MACCursorScale(rawValue: scaleValue) else { return nil }
        let cursor = MACCursorSwift()
        cursor.identifier = identifier
        cursor.frameCount = 1
        cursor.size = CursorGeometry.baseSize(matchingAspectOf: rep, frameCount: 1)
        let normalized = SlotImageImporter.normalized(
            rep,
            forScaleValue: scaleValue,
            pointWidth: CursorGeometry.normalizedPointWidth(cursor.size.width),
            frameCount: 1
        )
        cursor.setRepresentation(normalized, for: scale)
        return cursor
    }

    private func importAnimatedCursor(_ animated: SlotImageImporter.AnimatedImport, identifier: String) -> MACCursorSwift? {
        var scaleValue = SlotImageImporter.inferredScaleValue(forPixelWidth: animated.spriteSheet.pixelsWide)
        let factor = Int(scaleValue) / 100
        if factor > 1, (animated.spriteSheet.pixelsHigh / animated.frameCount) % factor != 0 {
            scaleValue = 100
        }
        guard let scale = MACCursorScale(rawValue: scaleValue) else { return nil }
        let cursor = MACCursorSwift()
        cursor.identifier = identifier
        cursor.frameCount = UInt(animated.frameCount)
        cursor.frameDuration = animated.frameDuration
        cursor.size = CursorGeometry.baseSize(matchingAspectOf: animated.spriteSheet,
                                              frameCount: animated.frameCount)
        let normalized = SlotImageImporter.normalized(
            animated.spriteSheet,
            forScaleValue: scaleValue,
            pointWidth: CursorGeometry.normalizedPointWidth(cursor.size.width),
            frameCount: animated.frameCount
        )
        cursor.setRepresentation(normalized, for: scale)
        return cursor
    }

    @discardableResult
    func assignSource(_ url: URL, toIdentifier identifier: String) -> Bool {
        if let existing = editingCursors.first(where: { $0.identifier == identifier }) {
            selectedCursorId = existing.id
            return true
        }
        guard let newCursor = importCursor(from: url, identifier: identifier) else {
            return false
        }
        pendingAdditions.append(newCursor)
        let model = CursorModel(from: newCursor, parentIdentifier: cursorTheme.backingLibrary.identifier)
        editingCursors.append(model)
        editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedCursorId = model.id
        return true
    }

    private func applyImported(_ imported: MACCursorSwift, to cursor: CursorModel) {
        cursor.frameCount = Int(imported.frameCount)
        cursor.frameDuration = imported.frameDuration
        cursor.hotSpot = CGPoint(x: imported.hotSpot.x, y: imported.hotSpot.y)
        cursor.size = CGSize(width: imported.size.width, height: imported.size.height)
        cursor.syncToBacking()
        if let reps = imported.representations as NSDictionary? {
            cursor.backingCursor.setValue(reps.mutableCopy(), forKey: "representations")
        }
        cursor.representationRevision += 1
    }

    @discardableResult
    func replaceSource(_ url: URL, for cursor: CursorModel) -> Bool {
        guard editingCursors.contains(where: { $0.id == cursor.id }),
              let imported = importCursor(from: url, identifier: cursor.identifier) else {
            return false
        }
        applyImported(imported, to: cursor)
        if hideTahoeCursors {
            for alias in MACConstants.tahoeAliases(for: cursor.identifier) {
                if let aliasCursor = editingCursors.first(where: { $0.identifier == alias }) {
                    applyImported(imported, to: aliasCursor)
                }
            }
        }
        selectedCursorId = cursor.id
        return true
    }

    func clearSlot(_ cursor: CursorModel, selectEmptyRow: Bool = true) {
        let identifier = cursor.identifier
        removeCursor(cursor)
        guard selectEmptyRow else { return }
        let isKnownSlot = CursorIdentifier.allIdentifiers(hideTahoeCursors: hideTahoeCursors)
            .contains { $0.identifier == identifier }
        if isKnownSlot {
            selectedCursorId = EditThemeSidebarModel.emptyRowPrefix + identifier
        }
    }

    func removeCursor(_ cursor: CursorModel) {
        performRemoveCursor(cursor)

        if hideTahoeCursors {
            let aliases = MACConstants.tahoeAliases(for: cursor.identifier)
            for alias in aliases {
                if let aliasCursor = editingCursors.first(where: { $0.identifier == alias }) {
                    performRemoveCursor(aliasCursor)
                }
            }
        }

    }

    private func performRemoveCursor(_ cursor: CursorModel) {
        if selectedCursorId == cursor.id {
            selectedCursorId = nil
        }
        if let idx = pendingAdditions.firstIndex(where: { $0 === cursor.backingCursor }) {
            pendingAdditions.remove(at: idx)
        } else if let original = originalMapping[cursor.id] {
            pendingRemovals.insert(original.backingCursor.identifier ?? "")
        }
        originalMapping.removeValue(forKey: cursor.id)
        editingCursors.removeAll { $0.id == cursor.id }
    }

    func duplicateCursor(_ cursor: CursorModel) {
        if let copy = cursor.backingCursor.copy() as? MACCursorSwift {
            copy.identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            pendingAdditions.append(copy)
            let model = CursorModel(from: copy, parentIdentifier: cursorTheme.backingLibrary.identifier)
            editingCursors.append(model)
            editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func importWindowsCursors(from urls: [URL]) {
        for url in urls {
            do {
                let cursor = try WindowsCursorImporter.importFile(from: url)
                pendingAdditions.append(cursor)
                let model = CursorModel(from: cursor, parentIdentifier: cursorTheme.backingLibrary.identifier)
                editingCursors.append(model)
            } catch {
                NSLog("CursorThemeEditorViewModel: Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        editingCursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
