import AppKit
import SwiftUI

enum ThemeFieldLimits {
    static let nameCharacterLimit = 30
    static let creatorCharacterLimit = 30
    static let versionFractionDigits = 1
    static let frameDurationFractionDigits = 2
}

enum CursorScaleInput {
    static let range: ClosedRange<Double> = 0.5...4.0
    static let sliderStep = 0.1
    static let fractionDigits = 2
    static let commitEpsilon = 0.0001
    static let systemDefault = 1.0

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return systemDefault }
        let snapped = (value * 100).rounded() / 100
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, snapped))
    }

    static func snapToStep(_ value: Double) -> Double {
        guard value.isFinite else { return systemDefault }
        return clamp((value / sliderStep).rounded() / 10.0)
    }

    static func format(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number
            .precision(.fractionLength(fractionDigits))
            .grouping(.never)
            .locale(latinDigits(locale)))
    }

    private static func latinDigits(_ locale: Locale) -> Locale {
        guard locale.numberingSystem != "latn" else { return locale }
        var components = Locale.Components(locale: locale)
        components.numberingSystem = "latn"
        return Locale(components: components)
    }

    static func parse(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    static func sanitize(_ input: String) -> String {
        var result = ""
        var separatorSeen = false
        var fractionDigitsSeen = 0
        for character in input {
            if character.isASCII && character.isNumber {
                if separatorSeen {
                    if fractionDigitsSeen < fractionDigits {
                        result.append(character)
                        fractionDigitsSeen += 1
                    }
                } else {
                    result.append(character)
                }
            } else if (character == "." || character == ",") && !separatorSeen {
                separatorSeen = true
                result.append(character)
            }
        }
        return result
    }
}

final class LimitedLengthFormatter: Formatter {
    var characterLimit = ThemeFieldLimits.nameCharacterLimit

    private static func resolvedEdit(
        proposed: String,
        original: String,
        replacing range: NSRange,
        limit: Int
    ) -> String {
        guard proposed.count > limit, proposed.count > original.count else { return proposed }
        let originalText = original as NSString
        let proposedText = proposed as NSString
        guard NSMaxRange(range) <= originalText.length else { return original }
        let head = originalText.substring(to: range.location)
        let tail = originalText.substring(from: NSMaxRange(range))
        let insertedLength = proposedText.length - range.location - (originalText.length - NSMaxRange(range))
        let room = limit - head.count - tail.count
        guard room > 0, insertedLength > 0,
              proposedText.substring(to: range.location) == head,
              proposedText.substring(from: range.location + insertedLength) == tail else { return original }
        let inserted = proposedText.substring(with: NSRange(location: range.location, length: insertedLength))
        return head + String(inserted.prefix(room)) + tail
    }

    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let proposed = partialStringPtr.pointee as String
        let resolved = Self.resolvedEdit(proposed: proposed,
                                         original: origString,
                                         replacing: origSelRange,
                                         limit: characterLimit)
        guard resolved != proposed else { return true }
        partialStringPtr.pointee = resolved as NSString
        let resolvedLength = (resolved as NSString).length
        let caret = resolved == origString
            ? min(origSelRange.location, resolvedLength)
            : resolvedLength - ((origString as NSString).length - NSMaxRange(origSelRange))
        proposedSelRangePtr?.pointee = NSRange(location: caret, length: 0)
        return false
    }
}

final class RestrictedNumberFormatter: NumberFormatter, @unchecked Sendable {
    var allowsFractionalInput = true

    static func sanitized(
        _ proposed: String,
        digits: Set<Character>,
        decimalSeparator: String,
        allowsFractionalInput: Bool
    ) -> String {
        var result = ""
        var separatorPlaced = false
        for character in proposed {
            if digits.contains(character) {
                result.append(character)
                continue
            }
            guard allowsFractionalInput, !separatorPlaced else { continue }
            if character == "." || character == "," || String(character) == decimalSeparator {
                result.append(decimalSeparator)
                separatorPlaced = true
            }
        }
        return result
    }

    private var cachedDigits: Set<Character>?
    private var cachedDigitsLocale: Locale?

    var acceptedDigits: Set<Character> {
        if let cachedDigits, cachedDigitsLocale == locale {
            return cachedDigits
        }
        var digits = Set<Character>("0123456789")
        let plain = NumberFormatter()
        plain.locale = locale
        plain.numberStyle = .none
        plain.usesGroupingSeparator = false
        for value in 0...9 {
            if let text = plain.string(from: NSNumber(value: value)) {
                digits.formUnion(text)
            }
        }
        cachedDigits = digits
        cachedDigitsLocale = locale
        return digits
    }

    func sanitizedInput(_ proposed: String) -> String {
        Self.sanitized(
            proposed,
            digits: acceptedDigits,
            decimalSeparator: decimalSeparator ?? ".",
            allowsFractionalInput: allowsFractionalInput)
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let proposed = partialStringPtr.pointee as String
        let cleaned = sanitizedInput(proposed)
        guard cleaned != proposed else { return true }
        partialStringPtr.pointee = cleaned as NSString
        let cleanedLength = (cleaned as NSString).length
        let dropped = (proposed as NSString).length - cleanedLength
        let requested = proposedSelRangePtr?.pointee.location ?? cleanedLength
        let caret = max(0, min(requested - dropped, cleanedLength))
        proposedSelRangePtr?.pointee = NSRange(location: caret, length: 0)
        return false
    }
}

enum NumericFieldValue {
    static let integerConvertibleBound = 0x1p53

    static func isCommittable(_ value: Double) -> Bool {
        value.isFinite && abs(value) <= integerConvertibleBound
    }

    static func integer(from value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded >= integerConvertibleBound { return Int(integerConvertibleBound) }
        if rounded <= -integerConvertibleBound { return Int(-integerConvertibleBound) }
        return Int(rounded)
    }
}

enum ValidatedTextFieldSync {
    @MainActor
    static func apply(_ text: String, to field: NSTextField) {
        field.stringValue = text
        guard let editor = field.currentEditor() else { return }
        editor.string = text
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    @MainActor
    static func apply(_ value: Double, to field: NSTextField) {
        field.objectValue = NSNumber(value: value)
        guard let editor = field.currentEditor() else { return }
        let text = field.stringValue
        editor.string = text
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }
}

enum ValidatedTextFieldFactory {
    @MainActor
    static func make(placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.isEditable = true
        field.isSelectable = true
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.drawsBackground = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.placeholderString = placeholder
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return field
    }
}

struct LimitedLengthTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var characterLimit: Int = ThemeFieldLimits.nameCharacterLimit

    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSTextField {
        let field = ValidatedTextFieldFactory.make(placeholder: placeholder)
        let formatter = LimitedLengthFormatter()
        formatter.characterLimit = characterLimit
        field.formatter = formatter
        field.delegate = context.coordinator
        field.stringValue = text
        field.isEnabled = isEnabled
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        if let formatter = nsView.formatter as? LimitedLengthFormatter,
           formatter.characterLimit != characterLimit {
            formatter.characterLimit = characterLimit
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        if nsView.isEnabled != isEnabled {
            nsView.isEnabled = isEnabled
        }
        guard coordinator.lastPushedText != text else { return }
        coordinator.lastPushedText = text
        if nsView.stringValue != text {
            ValidatedTextFieldSync.apply(text, to: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var lastPushedText: String?

        init(text: Binding<String>) {
            self.text = text
            self.lastPushedText = text.wrappedValue
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            push(field.stringValue)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            push(field.stringValue)
        }

        private func push(_ value: String) {
            lastPushedText = value
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}

struct GesturePlainTextView: NSViewRepresentable {
    let text: String
    let set: (String) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.set = set
        context.coordinator.cancel = cancel
        context.coordinator.show(text, in: scroll)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(set: set, cancel: cancel)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var set: (String) -> Void
        var cancel: () -> Void
        private let undo = UndoManager()
        private weak var view: NSTextView?

        init(set: @escaping (String) -> Void, cancel: @escaping () -> Void) {
            self.set = set
            self.cancel = cancel
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(undone), name: .NSUndoManagerDidUndoChange, object: undo)
            NotificationCenter.default.addObserver(self, selector: #selector(undone), name: .NSUndoManagerDidRedoChange, object: undo)
        }

        @objc private func undone() {
            guard let view else { return }
            set(view.string)
        }

        func makeView() -> NSScrollView {
            let scroll = NSTextView.scrollableTextView()
            scroll.drawsBackground = false
            if let view = scroll.documentView as? NSTextView {
                view.isRichText = false
                view.allowsUndo = true
                view.drawsBackground = false
                view.font = .systemFont(ofSize: NSFont.systemFontSize)
                view.isAutomaticQuoteSubstitutionEnabled = false
                view.isAutomaticDashSubstitutionEnabled = false
                view.isAutomaticTextReplacementEnabled = false
                view.isAutomaticSpellingCorrectionEnabled = false
                view.delegate = self
                self.view = view
            }
            return scroll
        }

        func show(_ text: String, in scroll: NSScrollView) {
            guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
            view.string = text
            undo.removeAllActions()
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undo
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.complete(_:)) else { return false }
            cancel()
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            set(view.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, view.hasMarkedText() else { return }
            set(view.string)
        }
    }
}

private struct NumericFieldPendingEditKey: EnvironmentKey {
    static var defaultValue: @MainActor (Bool) -> Void { { _ in } }
}

extension EnvironmentValues {
    var numericFieldPendingEdit: @MainActor (Bool) -> Void {
        get { self[NumericFieldPendingEditKey.self] }
        set { self[NumericFieldPendingEditKey.self] = newValue }
    }
}

struct NumericTextField: NSViewRepresentable {
    @Binding var value: Double
    var fractionDigits: Int = 0

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.numericFieldPendingEdit) private var reportPendingEdit

    private func makeFormatter() -> RestrictedNumberFormatter {
        let formatter = RestrictedNumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.allowsFractionalInput = fractionDigits > 0
        return formatter
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = ValidatedTextFieldFactory.make(placeholder: "")
        field.formatter = makeFormatter()
        field.delegate = context.coordinator
        field.objectValue = NSNumber(value: value)
        field.isEnabled = isEnabled
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.value = $value
        coordinator.reportPendingEdit = reportPendingEdit
        if let formatter = nsView.formatter as? RestrictedNumberFormatter,
           formatter.maximumFractionDigits != fractionDigits {
            nsView.formatter = makeFormatter()
        }
        if nsView.isEnabled != isEnabled {
            nsView.isEnabled = isEnabled
        }
        guard coordinator.lastPushedValue?.bitPattern != value.bitPattern else { return }
        coordinator.lastPushedValue = value
        coordinator.typedText = nil
        ValidatedTextFieldSync.apply(value, to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Double>
        var lastPushedValue: Double?
        var reportPendingEdit: @MainActor (Bool) -> Void = { _ in }
        var typedText: String? {
            didSet {
                guard (typedText == nil) != (oldValue == nil) else { return }
                reportPendingEdit(typedText != nil)
            }
        }

        init(value: Binding<Double>) {
            self.value = value
            self.lastPushedValue = value.wrappedValue
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let editor = field.currentEditor() else { return }
            typedText = editor.string == shownText(field) ? nil : editor.string
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            commit(field)
        }

        func control(
            _ control: NSControl,
            didFailToFormatString string: String,
            errorDescription error: String?
        ) -> Bool {
            return true
        }

        private func shownText(_ field: NSTextField) -> String? {
            field.formatter?.string(for: NSNumber(value: value.wrappedValue))
        }

        private func commit(_ field: NSTextField) {
            if let typedText,
               let formatter = field.formatter as? NumberFormatter,
               let parsed = formatter.number(from: typedText) {
                let candidate = parsed.doubleValue
                if NumericFieldValue.isCommittable(candidate), value.wrappedValue != candidate {
                    value.wrappedValue = candidate
                }
            }
            lastPushedValue = value.wrappedValue
            field.objectValue = NSNumber(value: value.wrappedValue)
            typedText = nil
        }
    }
}
