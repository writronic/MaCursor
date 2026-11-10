import CoreGraphics

@MainActor
struct MACBackgroundCursor {
    struct Operations {
        var set: (Bool) -> Bool = { on in
            let connection = CGSMainConnectionID()
            return CGSSetConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse) == .success
        }
    }

    let operations: Operations
    private(set) var isOn = false

    init(operations: Operations = Operations()) {
        self.operations = operations
    }

    mutating func turnOn() {
        guard !isOn else { return }
        isOn = operations.set(true)
    }

    mutating func turnOff() {
        guard isOn else { return }
        isOn = false
        _ = operations.set(false)
    }
}
