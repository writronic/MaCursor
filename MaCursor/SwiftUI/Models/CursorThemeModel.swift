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

        self.cursors = library.cursors
            .map { CursorModel(from: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func syncToObjC() {
        if name != backingLibrary.name {
            let taken = Set(backingLibrary.library?.themes.compactMap { $0 === backingLibrary ? nil : $0.identifier } ?? [])
            let unique = CursorLibrary.uniqueIdentity(forName: name, avoiding: taken)
            name = unique.name
            backingLibrary.identifier = unique.identifier
        }

        backingLibrary.name = name
        backingLibrary.creator = creator
        backingLibrary.version = NSNumber(value: version)
        backingLibrary.isHiDPI = isHiDPI

        for cursor in cursors {
            cursor.syncToBacking()
        }
    }

    func save() -> Error? {
        let oldName = backingLibrary.name
        let oldId = backingLibrary.identifier
        syncToObjC()
        if let error = backingLibrary.save() {
            name = oldName
            backingLibrary.name = oldName
            backingLibrary.identifier = oldId
            return error
        }
        if backingLibrary.identifier != oldId {
            NotificationCenter.default.post(
                name: .cursorLibraryIdentifierDidChange,
                object: self,
                userInfo: ["oldId": oldId, "newId": backingLibrary.identifier]
            )
        }
        return nil
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

    var openEditorCount = 0

    func refreshFromObjC() {
        name = backingLibrary.name
        creator = backingLibrary.creator
        version = backingLibrary.version.doubleValue
        isHiDPI = backingLibrary.isHiDPI
        fileURL = backingLibrary.fileURL

        cursors = backingLibrary.cursors
            .map { CursorModel(from: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addCursor() {
        let newCursor = MACCursorSwift()
        backingLibrary.addCursor(newCursor)
        let model = CursorModel(from: newCursor)
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
