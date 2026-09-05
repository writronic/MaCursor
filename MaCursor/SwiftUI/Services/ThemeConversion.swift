import AppKit
import Combine
import Foundation

enum TahoeVariantSynthesizer {
    static let pairs: [(base: String, variant: String)] = [
        ("com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS"),
        ("com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS"),
    ]

    static func addingVariants(to cursors: [String: AnimatedCursor]) -> [String: AnimatedCursor] {
        var result = cursors
        for pair in pairs {
            if let base = cursors[pair.base], result[pair.variant] == nil {
                result[pair.variant] = base
            }
        }
        return result
    }
}

final class ConvertPanelFilter: NSObject, NSOpenSavePanelDelegate {
    static func allowsSelecting(_ url: URL) -> Bool {
        guard ThemeImporter.unsupportedFileReasonByName(url) != nil else { return true }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        Self.allowsSelecting(url)
    }
}

struct ConversionOutcome: Sendable {
    let cursorFileURL: URL
    let previewURL: URL?
    let report: ImportReport
    let buildWarnings: [ImportWarning]
    let suggestedName: String
    let suggestedCreator: String
    fileprivate let workingDirectory: URL
}

enum ThemeConversionService {
    static func convert(input: URL) throws -> ConversionOutcome {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaCursor-Convert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let (build, report, name, creator): (ThemeBuildResult, ImportReport, String, String)
        do {
            (build, report, name, creator) = try ThemeImporter.withImportResult(from: input) { result in
                let cursors = TahoeVariantSynthesizer.addingVariants(
                    to: result.cursors.mapValues { $0.cursor })
                let themeName = result.metadata.name.isEmpty
                    ? input.deletingPathExtension().lastPathComponent
                    : result.metadata.name
                let author = result.metadata.author?.trimmingCharacters(in: .whitespacesAndNewlines)
                let creator = (author?.isEmpty == false) ? author! : NSUserName()
                let built = try CursorThemeWriter.build(
                    cursors: cursors,
                    themeName: themeName,
                    creator: creator,
                    outputDirectory: workDir,
                    writePreview: true
                )
                return (built, result.report, themeName, creator)
            }
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            throw error
        }

        return ConversionOutcome(
            cursorFileURL: build.cursorFileURL,
            previewURL: build.previewURL,
            report: report,
            buildWarnings: build.warnings,
            suggestedName: name,
            suggestedCreator: creator,
            workingDirectory: workDir
        )
    }

    static func discard(_ outcome: ConversionOutcome) {
        try? FileManager.default.removeItem(at: outcome.workingDirectory)
    }
}

@MainActor
protocol ThemeLibraryLanding {
    func importTheme(at url: URL)
    @discardableResult func importThemeReturningId(at url: URL) -> String?
}

@MainActor final class ThemeConversionCoordinator: ObservableObject {
    enum Phase: Equatable { case idle, converting, review, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var outcome: ConversionOutcome?

    func convert(_ input: URL) async {
        phase = .converting
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ThemeConversionService.convert(input: input)
            }.value
            outcome = result
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func confirmAddToLibrary(using library: ThemeLibraryLanding) {
        guard let outcome else { return }
        library.importTheme(at: outcome.cursorFileURL)
        ThemeConversionService.discard(outcome)
        self.outcome = nil
        phase = .idle
    }

    @discardableResult
    func confirmAndEditReturningId(using library: ThemeLibraryLanding) -> String? {
        guard let outcome else { return nil }
        let newId = library.importThemeReturningId(at: outcome.cursorFileURL)
        ThemeConversionService.discard(outcome)
        self.outcome = nil
        phase = .idle
        return newId
    }

    func cancel() {
        if let outcome { ThemeConversionService.discard(outcome) }
        outcome = nil
        phase = .idle
    }
}
