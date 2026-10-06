import AppKit
import ApplicationServices
import VibeTranslatorCore

enum AccessMode: String, CaseIterable, Identifiable {
    case automatic, accessibility, clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automático")
        case .accessibility: String(localized: "Accesibilidad (directo)")
        case .clipboard: String(localized: "Portapapeles (⌘A ⌘C ⌘V)")
        }
    }
}

enum AccessMethod: String {
    case accessibility, clipboard

    var title: String {
        switch self {
        case .accessibility: String(localized: "Accesibilidad")
        case .clipboard: String(localized: "Portapapeles")
        }
    }
}

/// "Which text field is this?" Used to refuse a replacement if the user moved to
/// another channel, window or app while the translation was running.
struct FieldIdentity {
    let pid: pid_t
    let windowTitle: String?
    let element: AXUIElement?

    func matches(_ other: FieldIdentity) -> Bool {
        guard pid == other.pid, windowTitle == other.windowTitle else { return false }
        // Electron may expose the focused element late; only compare when both reads saw it.
        if let element, let otherElement = other.element {
            return CFEqual(element, otherElement)
        }
        return true
    }

    /// Discord prefixes the title with unread counters, which change on their own.
    static func normalizeTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"^(?:\(\d+\)\s*|[•●]\s*)+"#, with: "", options: .regularExpression)
    }
}

struct DraftSnapshot {
    let identity: FieldIdentity
    let text: String
    let method: AccessMethod
}

enum DraftAccessError: LocalizedError {
    case appSwitched
    case focusNotInTextField(role: String)
    case noReadableField
    case copyFailed
    case fieldChanged
    case draftChanged
    case writeFailed(String)
    case verificationFailed
    case noSelection
    case selectionChanged

    var errorDescription: String? {
        switch self {
        case .appSwitched:
            String(localized: "Has cambiado de app durante la traducción. No se ha reemplazado nada.")
        case let .focusNotInTextField(role):
            String(localized: "El foco no está en el cuadro de mensaje (elemento \(role)). Haz clic en el borrador y vuelve a intentarlo.")
        case .noReadableField:
            String(localized: "No se puede leer el campo activo por Accesibilidad. Prueba el método Portapapeles en Ajustes.")
        case .copyFailed:
            String(localized: "No se pudo copiar el borrador. ¿Está vacío o el cursor no está en el cuadro de mensaje?")
        case .fieldChanged:
            String(localized: "El campo activo ha cambiado (otro canal o ventana). No se ha reemplazado nada.")
        case .draftChanged:
            String(localized: "El borrador ha cambiado mientras se traducía. No se ha reemplazado nada.")
        case let .writeFailed(reason):
            String(localized: "La app no aceptó el texto por Accesibilidad (\(reason)); el borrador sigue intacto. Prueba el método Automático o Portapapeles.")
        case .verificationFailed:
            String(localized: "El editor modificó el borrador de forma inesperada al escribir la traducción. Revísalo; el original está en el menú › Copiar original.")
        case .noSelection:
            String(localized: "Selecciona primero el texto que quieres traducir.")
        case .selectionChanged:
            String(localized: "La selección ha cambiado. Vuelve a seleccionar el texto y tradúcelo de nuevo.")
        }
    }
}

/// Reads and replaces the draft in the frontmost app's focused text field, either
/// through Accessibility or through automated ⌘A ⌘C / ⌘V with the clipboard preserved.
@MainActor
final class DraftAccessor {
    let app: NSRunningApplication
    let mode: AccessMode
    let isElectron: Bool
    let axApp: AXUIElement
    /// Result of opting the app into a full AX tree (Electron only).
    let manualAccessibilityResult: AXError?

    init(app: NSRunningApplication, mode: AccessMode) {
        self.app = app
        self.mode = mode
        self.axApp = Accessibility.application(app.processIdentifier)
        self.isElectron = Accessibility.isElectron(app)
        self.manualAccessibilityResult = isElectron ? Accessibility.enableManualAccessibility(axApp) : nil
    }

    var pid: pid_t { app.processIdentifier }

    // MARK: Reading

    func capture(using forcedMethod: AccessMethod? = nil) async throws -> DraftSnapshot {
        try ensureFrontmost()
        let element = await focusedElement()
        if let element, !element.isTextInput {
            throw DraftAccessError.focusNotInTextField(role: element.role ?? String(localized: "desconocido"))
        }
        let identity = identity(focused: element)
        let method = forcedMethod ?? readMethod(for: element)

        switch method {
        case .accessibility:
            guard let value = element?.stringValue else { throw DraftAccessError.noReadableField }
            return DraftSnapshot(identity: identity, text: value, method: .accessibility)
        case .clipboard:
            return DraftSnapshot(identity: identity, text: try await copyAll(), method: .clipboard)
        }
    }

    private func readMethod(for element: AXUIElement?) -> AccessMethod {
        switch mode {
        case .accessibility:
            return .accessibility
        case .clipboard:
            return .clipboard
        case .automatic:
            // Rich web editors (Discord runs Slate inside Electron) keep their own document
            // model: writing through AX can update the DOM but not what gets sent, while their
            // copy/paste handlers round-trip mentions and custom emoji (<@id>, <:name:id>).
            if isElectron { return .clipboard }
            guard
                let element,
                let value = element.stringValue,
                !value.contains("\u{FFFC}"), // embedded objects AX can't spell out
                element.isSettable(kAXSelectedTextAttribute) || element.isSettable(kAXValueAttribute)
            else { return .clipboard }
            return .accessibility
        }
    }

    /// Focused element of the target app. Electron builds its tree lazily after the opt-in.
    func focusedElement() async -> AXUIElement? {
        for attempt in 0..<6 {
            if let element = axApp.element(kAXFocusedUIElementAttribute) { return element }
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 50 : 100))
        }
        return nil
    }

    var focusedWindowTitle: String? {
        axApp.element(kAXFocusedWindowAttribute)?.string(kAXTitleAttribute)
    }

    func identity(focused element: AXUIElement?) -> FieldIdentity {
        FieldIdentity(
            pid: pid,
            windowTitle: focusedWindowTitle.map(FieldIdentity.normalizeTitle),
            element: element?.isTextInput == true ? element : nil
        )
    }

    // MARK: Writing

    /// Replaces the whole draft, but only if the same field still holds the same text.
    func replace(_ snapshot: DraftSnapshot, with newText: String) async throws {
        try ensureFrontmost()
        let element = await focusedElement()
        guard identity(focused: element).matches(snapshot.identity) else { throw DraftAccessError.fieldChanged }

        switch snapshot.method {
        case .accessibility:
            try await replaceViaAccessibility(element, expected: snapshot.text, with: newText)
        case .clipboard:
            try await replaceViaClipboard(expected: snapshot.text, with: newText)
        }
    }

    private func replaceViaAccessibility(_ element: AXUIElement?, expected: String, with newText: String) async throws {
        guard let element, let current = element.stringValue else { throw DraftAccessError.fieldChanged }
        guard DraftText.isSame(current, expected) else { throw DraftAccessError.draftChanged }

        // Replacing the selection goes through the editor's input pipeline (like dictation);
        // setting AXValue is the blunt fallback. Web editors apply AX requests asynchronously,
        // so only write once the select-all is visible, or the text would be inserted at the caret.
        let fullLength = (current as NSString).length
        var result = AXError.attributeUnsupported
        if element.isSettable(kAXSelectedTextAttribute),
           element.selectAll(of: current) == .success,
           await waitUntil({ element.selectedRange.map { $0.location == 0 && $0.length == fullLength } == true }) {
            result = element.set(kAXSelectedTextAttribute, newText as CFString)
        }
        if result != .success, element.isSettable(kAXValueAttribute) {
            result = element.set(kAXValueAttribute, newText as CFString)
        }

        if result == .success, await waitUntil(timeout: .milliseconds(800), { DraftText.isSame(element.stringValue ?? "", newText) }) {
            return
        }

        let after = element.stringValue ?? ""
        guard DraftText.isSame(after, expected) else {
            // The editor changed, but not into the translation: don't touch it again.
            throw DraftAccessError.verificationFailed
        }
        // Nothing landed, so the clipboard route is still safe to try.
        if mode == .automatic {
            try await replaceViaClipboard(expected: expected, with: newText)
            return
        }
        throw DraftAccessError.writeFailed(result == .success ? String(localized: "el editor ignoró el cambio") : result.name)
    }

    private func waitUntil(timeout: Duration = .milliseconds(300), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    private func replaceViaClipboard(expected: String, with newText: String) async throws {
        let saved = ClipboardSnapshot()
        let current: String
        do {
            current = try await selectAllAndCopy()
        } catch {
            saved.restore()
            throw error
        }
        guard DraftText.isSame(current, expected) else {
            saved.restore()
            await KeyboardSimulator.collapseSelectionToEnd()
            throw DraftAccessError.draftChanged
        }
        do {
            try ensureFrontmost()
        } catch {
            saved.restore()
            throw error
        }

        let ours = Clipboard.writeTransient(newText)
        await KeyboardSimulator.command("v")
        // The target reads the pasteboard asynchronously while it handles ⌘V.
        try? await Task.sleep(for: .milliseconds(400))
        saved.restore(ifChangeCountIs: ours)
    }

    // MARK: Clipboard primitives

    /// ⌘A ⌘C with the user's clipboard restored afterwards. Leaves the draft selected.
    func copyAll() async throws -> String {
        let saved = ClipboardSnapshot()
        defer { saved.restore() }
        return try await selectAllAndCopy()
    }

    private func selectAllAndCopy() async throws -> String {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        await KeyboardSimulator.command("a")
        try ensureFrontmost()
        await KeyboardSimulator.command("c")
        guard await Clipboard.waitForChange(from: before) else { throw DraftAccessError.copyFailed }
        return pasteboard.string(forType: .string) ?? ""
    }

    /// After a clipboard read the whole draft stays selected; one stray key would wipe it.
    func deselectIfStillFrontmost(after snapshot: DraftSnapshot) async {
        guard snapshot.method == .clipboard, (try? ensureFrontmost()) != nil else { return }
        await KeyboardSimulator.collapseSelectionToEnd()
    }

    func ensureFrontmost() throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw DraftAccessError.appSwitched
        }
    }
}
