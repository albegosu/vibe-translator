import AppKit
import ApplicationServices
import VibeTranslatorCore

/// Text the user selected, plus enough context to replace exactly that selection later.
struct SelectionSnapshot {
    let identity: FieldIdentity
    /// Plain selection. Replace compares against this, never against the structured source:
    /// a later ⌘C returns this text, not the HTML conversion.
    let text: String
    /// What the translator sees. Equals `text` except for a web selection, where headings,
    /// lists and code are recovered from the pasteboard HTML.
    let source: String
    let method: AccessMethod
    /// The selection lives in a text field, so it can be replaced.
    let isEditable: Bool
}

extension DraftAccessor {
    /// Reads the current selection without changing it.
    ///
    /// A native field comes from Accessibility, whose selected text already has its line
    /// breaks. A web page does not: `AXSelectedText` joins every block with spaces, so the
    /// selection is copied instead and rebuilt from the HTML. Electron stays on the plain
    /// copy, because that is the form that round-trips mentions and custom emoji.
    func captureSelection() async throws -> SelectionSnapshot {
        try ensureFrontmost()
        let element = await focusedElement()
        let identity = identity(focused: element)
        let isEditable = element?.isTextInput == true
        // Electron builds its accessibility tree lazily; don't walk it just to decide.
        let insideWeb = !isElectron && element?.isInsideWebArea == true

        if WebSelection.shouldStructure(
            isElectron: isElectron,
            isBrowser: WebSelection.isBrowser(bundleIdentifier: app.bundleIdentifier),
            isInsideWebArea: insideWeb,
            isNativeTextField: isEditable && !insideWeb
        ) {
            return try await captureCopiedSelection(identity: identity, isEditable: isEditable, structure: true)
        }

        if !isElectron, let selected = element?.string(kAXSelectedTextAttribute), DraftText.hasLetters(selected) {
            return SelectionSnapshot(identity: identity, text: selected, source: selected, method: .accessibility, isEditable: isEditable)
        }
        return try await captureCopiedSelection(identity: identity, isEditable: isEditable, structure: false)
    }

    /// Replaces the selection, but only if the same field still has the same text selected.
    func replaceSelection(_ snapshot: SelectionSnapshot, with newText: String) async throws {
        try ensureFrontmost()
        let element = await focusedElement()
        guard identity(focused: element).matches(snapshot.identity) else { throw DraftAccessError.fieldChanged }

        switch snapshot.method {
        case .accessibility:
            guard let element, let current = element.string(kAXSelectedTextAttribute), DraftText.isSame(current, snapshot.text) else {
                throw DraftAccessError.selectionChanged
            }
            let result = element.set(kAXSelectedTextAttribute, newText as CFString)
            guard result == .success else { throw DraftAccessError.writeFailed(result.name) }

        case .clipboard:
            let saved = ClipboardSnapshot()
            let current: String
            do {
                current = try await copyCurrentSelection().plain
            } catch {
                saved.restore()
                throw DraftAccessError.selectionChanged
            }
            guard DraftText.isSame(current, snapshot.text) else {
                saved.restore()
                throw DraftAccessError.selectionChanged
            }
            let ours = Clipboard.writeTransient(newText)
            await KeyboardSimulator.command("v")
            try? await Task.sleep(for: .milliseconds(400))
            saved.restore(ifChangeCountIs: ours)
        }
    }

    private func captureCopiedSelection(identity: FieldIdentity, isEditable: Bool, structure: Bool) async throws -> SelectionSnapshot {
        let saved = ClipboardSnapshot()
        defer { saved.restore() }
        let copied = try await copyCurrentSelection()
        let source = structure ? WebSelection.translationSource(plain: copied.plain, html: copied.html) : copied.plain
        return SelectionSnapshot(identity: identity, text: copied.plain, source: source, method: .clipboard, isEditable: isEditable)
    }

    /// What ⌘C just put on the pasteboard. The plain string is the selection itself;
    /// HTML is only present for a rich copy and is never written back.
    private struct CopiedSelection {
        var plain: String
        var html: String?
    }

    /// ⌘C on whatever is selected. Leaves the copied text on the pasteboard.
    private func copyCurrentSelection() async throws -> CopiedSelection {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        await KeyboardSimulator.command("c")
        guard await Clipboard.waitForChange(from: before, timeout: .milliseconds(600)),
              let text = pasteboard.string(forType: .string), DraftText.hasLetters(text) else {
            throw DraftAccessError.noSelection
        }
        return CopiedSelection(plain: text, html: Self.htmlString(on: pasteboard))
    }

    private static let htmlTypes: [NSPasteboard.PasteboardType] = [
        .html,
        NSPasteboard.PasteboardType("Apple HTML pasteboard type"),
        NSPasteboard.PasteboardType("text/html"),
    ]

    private static func htmlString(on pasteboard: NSPasteboard) -> String? {
        for item in pasteboard.pasteboardItems ?? [] {
            for type in htmlTypes {
                if let html = item.string(forType: type), html.contains("<") {
                    return html
                }
            }
        }
        return nil
    }
}
