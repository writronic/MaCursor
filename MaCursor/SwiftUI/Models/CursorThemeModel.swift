import Combine
import Foundation

class CursorThemeModel: ObservableObject, Identifiable, Hashable {
    var id: String { backingLibrary.identifier }
    @Published var name: String
    @Published var creator: String
    @Published var version: Double
    @Published var isHiDPI: Bool
    @Published var cursors: [CursorModel]
    @Published var isApplied: Bool = false
    @Published var fileURL: URL?

    let backingLibrary: CursorLibrary

    init(from library: CursorLibrary) {
        self.backingLibrary = library
        self.name = library.name
        self.creator = library.creator
        self.version = library.version.doubleValue
        self.isHiDPI = library.isHiDPI
        self.fileURL = library.fileURL

        let parentId = library.identifier
        self.cursors = library.cursors
            .map { CursorModel(from: $0, parentIdentifier: parentId) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func syncToObjC() {
        let oldId = backingLibrary.identifier
        let nameChanged = (name != backingLibrary.name)

        backingLibrary.name = name
        backingLibrary.creator = creator
        backingLibrary.version = NSNumber(value: version)
        backingLibrary.isHiDPI = isHiDPI

        if nameChanged {
            let newId = CursorLibrary.updateIdentifier(oldId, newName: name)
            backingLibrary.identifier = newId

            NotificationCenter.default.post(
                name: .cursorLibraryIdentifierDidChange,
                object: self,
                userInfo: ["oldId": oldId, "newId": newId]
            )
        }

        for cursor in cursors {
            cursor.syncToBacking()
        }
    }

    func save() -> Error? {
        syncToObjC()
        return backingLibrary.save()
    }

    func revertToSaved() {
        backingLibrary.revertToSaved()
        refreshFromObjC()
    }

    var isDirty: Bool {
        backingLibrary.isDirty
    }

    var isApplicable: Bool {
        cursors.contains { $0.backingCursor.isApplicable }
    }

    func refreshFromObjC() {
        name = backingLibrary.name
        creator = backingLibrary.creator
        version = backingLibrary.version.doubleValue
        isHiDPI = backingLibrary.isHiDPI
        fileURL = backingLibrary.fileURL

        let parentId = backingLibrary.identifier
        cursors = backingLibrary.cursors
            .map { CursorModel(from: $0, parentIdentifier: parentId) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addCursor() {
        let newCursor = MACCursorSwift()
        backingLibrary.addCursor(newCursor)
        let model = CursorModel(from: newCursor, parentIdentifier: backingLibrary.identifier)
        cursors.append(model)
        cursors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func removeCursor(_ cursor: CursorModel) {
        backingLibrary.removeCursor(cursor.backingCursor)
        cursors.removeAll { $0.id == cursor.id }
    }


    static func == (lhs: CursorThemeModel, rhs: CursorThemeModel) -> Bool {
        lhs.backingLibrary === rhs.backingLibrary
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(backingLibrary))
    }
}
