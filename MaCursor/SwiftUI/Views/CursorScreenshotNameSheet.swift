import SwiftUI

struct CursorScreenshotNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var opened: CursorScreenshotNaming
    @State private var draft: CursorScreenshotNaming
    @State private var sample = CursorScreenshotNameContext(date: Date(), app: "Safari", title: "GitHub")

    init(opened: CursorScreenshotNaming) {
        _opened = State(initialValue: opened)
        _draft = State(initialValue: opened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type text and drag elements to create a custom format:")

            VStack(alignment: .leading, spacing: 6) {
                TextField("File name format", text: $draft.format)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)

                Text(verbatim: draft.stem(sample))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(alignment: .top, spacing: 24) {
                ForEach(CursorScreenshotNameToken.columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(column, id: \.self) { token in
                            pill(token)
                        }
                    }
                }
            }

            Toggle("Remove illegal characters", isOn: $draft.removesIllegalCharacters)
                .toggleStyle(.checkbox)

            if draft.counts {
                LabeledContent("Next number") {
                    TextField("Next number", value: $draft.nextNumber, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            HStack {
                Button("Restore Defaults") { draft = draft.restoringDefaults() }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("OK") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func pill(_ token: CursorScreenshotNameToken) -> some View {
        Button {
            draft.format += token.code
        } label: {
            HStack(spacing: 4) {
                title(token)
                Text(verbatim: token.code)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: token.code as NSString) }
    }

    @ViewBuilder private func title(_ token: CursorScreenshotNameToken) -> some View {
        switch token {
        case .date: Text("Date")
        case .year: Text("Year")
        case .month: Text("Month (numeric)")
        case .day: Text("Day")
        case .windowTitle: Text("Window title")
        case .appName: Text("App name")
        case .hour: Text("Hour")
        case .minutes: Text("Minutes")
        case .seconds: Text("Seconds")
        case .amPM: Text("AM/PM")
        case .number: Text("Auto-increment")
        }
    }

    private func save() {
        var config = CursorScreenshotConfig.load()
        config.naming = config.naming.keepingSheet(draft, opened: opened)
        config.save()
    }
}
