import AppKit
import ApplicationServices
import VibeTranslatorCore

/// Text the user selected, plus enough context to replace exactly that selection later.
struct SelectionSnapshot {
    let identity: FieldIdentity
    let text: String
    let method: AccessMethod
    /// The selection lives in a text field, so it can be replaced.
    let isEditable: Bool
}

extension DraftAccessor {
    /// Reads the current selection without changing it: Accessibility in native apps,
    /// ⌘C (clipboard restored) in Electron apps or when AX has nothing.
    func captureSelection() async throws -> SelectionSnapshot {
        try ensureFrontmost()
        let element = await focusedElement()
        let identity = identity(focused: element)
        let isEditable = element?.isTextInput == true

        if !isElectron, let selected = element?.string(kAXSelectedTextAttribute), DraftText.hasLetters(selected) {
            return SelectionSnapshot(identity: identity, text: selected, method: .accessibility, isEditable: isEditable)
        }
        let saved = ClipboardSnapshot()
        defer { saved.restore() }
        let copied = try await copyCurrentSelection()
        return SelectionSnapshot(identity: identity, text: copied, method: .clipboard, isEditable: isEditable)
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
                current = try await copyCurrentSelection()
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

    /// ⌘C on whatever is selected. Leaves the copied text on the pasteboard.
    private func copyCurrentSelection() async throws -> String {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        await KeyboardSimulator.command("c")
        guard await Clipboard.waitForChange(from: before, timeout: .milliseconds(600)),
              let text = pasteboard.string(forType: .string), DraftText.hasLetters(text) else {
            throw DraftAccessError.noSelection
        }
        return text
    }
}
