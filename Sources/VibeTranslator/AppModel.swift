import AppKit
import Observation
import os
import Translation
import VibeTranslatorCore

struct LastTranslation {
    let identity: FieldIdentity
    let appName: String
    let original: String
    let translated: String
    let method: AccessMethod
    var restored = false
}

enum AppError: LocalizedError {
    case accessibilityDenied
    case noFrontmostApp
    case appNotAllowed(String)
    case emptyDraft
    case nothingChanged
    case nothingToRestore
    case restoreMismatch
    case selectPromptInTerminal
    case promptTooLong
    case draftInTerminal
    case sameLanguages
    case draftTooLong

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "VibeTranslator necesita permiso de Accesibilidad (Ajustes del Sistema › Privacidad y seguridad › Accesibilidad)."
        case .noFrontmostApp:
            "No hay ninguna app activa."
        case let .appNotAllowed(name):
            "Has limitado la traducción del borrador a otras apps y \(name) no está en la lista. Puedes cambiarlo en Ajustes › General."
        case .emptyDraft:
            "El borrador está vacío o no tiene texto que traducir."
        case .nothingChanged:
            "La traducción es idéntica al borrador; no se ha cambiado nada."
        case .nothingToRestore:
            "No hay ninguna traducción que deshacer."
        case .restoreMismatch:
            "Has editado el borrador después de traducirlo, así que no se sobrescribe. Usa «Copiar original» en el menú."
        case .selectPromptInTerminal:
            "En la terminal, selecciona primero el texto del prompt."
        case .promptTooLong:
            "El campo es demasiado largo para ser un prompt. Selecciona la parte que quieres mejorar."
        case .sameLanguages:
            "«Mi idioma» y «Traducir a» son el mismo idioma. Cámbialos en Ajustes › Traducción."
        case .draftInTerminal:
            "En la terminal no se traduce el borrador entero. Selecciona el texto y usa «Traducir selección» o «Mejorar prompt»."
        case .draftTooLong:
            "El texto es demasiado largo para un borrador (más de 4.000 caracteres). Selecciona la parte que quieres y usa «Traducir selección»."
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// Draft direction: my language → the target language.
    var draftSource: Locale.Language { settings.nativeLanguage.language }
    var draftTarget: Locale.Language { settings.targetLanguage.language }

    var languagePairLabel: String {
        "\(settings.nativeLanguage.languageName()) → \(settings.targetLanguage.languageName())"
    }

    let settings = AppSettings()
    private(set) var isBusy = false
    private(set) var isTrusted = Accessibility.isTrusted
    private(set) var languageStatus: LanguageAvailability.Status?
    private(set) var lastTranslation: LastTranslation?
    private(set) var hotKeyProblem: String?
    private(set) var diagnosticsReport: String?
    private(set) var diagnosticsFile: URL?
    private(set) var appleIntelligenceStatus = AppleIntelligenceEngine.statusText
    private(set) var ollamaModels: [OllamaModel] = []
    private(set) var ollamaStatus: String?

    @ObservationIgnored let hud = HUD()
    @ObservationIgnored let selectionPanel = SelectionPanel()
    @ObservationIgnored let windows = WindowPresenter()
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    @ObservationIgnored private let appleTranslation = AppleTranslationEngine()
    @ObservationIgnored private var trustPolling: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "io.github.albegosu.VibeTranslator", category: "app")

    /// The chosen engine first, then Apple Translation as the safety net.
    private func makeTranslator(from source: Locale.Language? = nil, to target: Locale.Language? = nil) -> DraftTranslator {
        var engines: [any TranslationEngine] = []
        switch settings.engine {
        case .appleIntelligence:
            engines.append(AppleIntelligenceEngine(style: settings.style))
        case .ollama:
            engines.append(OllamaEngine(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel, style: settings.style))
        case .appleTranslation:
            break
        }
        engines.append(appleTranslation)
        return DraftTranslator(engines: engines, source: source ?? draftSource, target: target ?? draftTarget, engineTimeout: .seconds(20))
    }

    func start() {
        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            Task {
                switch action {
                case .translate: await self.translateDraft()
                case .restore: await self.restoreOriginal()
                case .translateSelection: await self.translateSelection()
                case .improvePrompt: await self.improvePrompt()
                }
            }
        }
        hotKeys.install()
        settings.onShortcutsChanged = { [weak self] in self?.registerHotKeys() }
        settings.onLanguagesChanged = { [weak self] in
            Task { await self?.refreshLanguageStatus() }
        }
        registerHotKeys()

        if !isTrusted {
            Accessibility.requestTrust()
            startTrustPolling()
        }
        Task {
            await refreshLanguageStatus()
            await refreshEngineStatus()
        }
    }

    // MARK: Translate

    func translateDraft() async {
        guard !isBusy else {
            hud.show("Ya hay una traducción en curso.", style: .info)
            return
        }
        isBusy = true
        defer { isBusy = false }

        var accessor: DraftAccessor?
        var snapshot: DraftSnapshot?
        var pending: LastTranslation?
        do {
            guard settings.languagesAreValid else { throw AppError.sameLanguages }
            let target = try prepareAccessor()
            accessor = target
            await KeyboardSimulator.waitForModifierRelease()

            let captured = try await target.capture()
            snapshot = captured
            guard DraftText.hasLetters(captured.text) else { throw AppError.emptyDraft }
            // ⌘A in a code editor selects the whole file: that's not a draft.
            guard captured.text.count <= 4_000 else { throw AppError.draftTooLong }

            hud.show("Traduciendo…", style: .progress)
            let translator = makeTranslator()
            let source = captured.text
            let translation = try await withTimeout(.seconds(45)) { try await translator.translate(source) }
            guard !DraftText.isSame(translation.text, captured.text) else { throw AppError.nothingChanged }

            pending = LastTranslation(
                identity: captured.identity,
                appName: target.app.localizedName ?? "Discord",
                original: captured.text,
                translated: translation.text,
                method: captured.method
            )
            try await target.replace(captured, with: translation.text)
            lastTranslation = pending
            log.info("Translated \(translation.translatedLines) lines (\(translation.fallbackLines) by fragments) with \(translation.engineName ?? "-") via \(captured.method.rawValue)")
            showResult(of: translation)
        } catch {
            // The draft may now hold something unexpected: keep the original reachable from the menu.
            if case DraftAccessError.verificationFailed = error, let pending {
                lastTranslation = pending
            }
            if let accessor, let snapshot { await accessor.deselectIfStillFrontmost(after: snapshot) }
            fail(error)
        }
    }

    // MARK: Restore

    func restoreOriginal() async {
        guard !isBusy else { return }
        guard let last = lastTranslation, !last.restored else {
            fail(AppError.nothingToRestore)
            return
        }
        isBusy = true
        defer { isBusy = false }

        var accessor: DraftAccessor?
        var snapshot: DraftSnapshot?
        do {
            let target = try prepareAccessor()
            accessor = target
            guard target.pid == last.identity.pid else { throw DraftAccessError.fieldChanged }
            await KeyboardSimulator.waitForModifierRelease()

            let current = try await target.capture(using: last.method)
            snapshot = current
            guard current.identity.matches(last.identity) else { throw DraftAccessError.fieldChanged }
            guard DraftText.isSame(current.text, last.translated) else { throw AppError.restoreMismatch }

            try await target.replace(current, with: last.original)
            lastTranslation?.restored = true
            hud.show("Texto original restaurado.", style: .success)
        } catch {
            if let accessor, let snapshot { await accessor.deselectIfStillFrontmost(after: snapshot) }
            fail(error, hint: "Puedes usar «Copiar original» en el menú.")
        }
    }

    private func showResult(of translation: DraftTranslation) {
        let engine = translation.engineName ?? "el motor"
        guard let failure = translation.failures.first else {
            hud.show("Traducido con \(engine). Revísalo y envíalo cuando quieras.", style: .success)
            return
        }
        hud.show("Traducido con \(engine): \(failure.engineName) falló (\(failure.message))", style: .info, duration: .seconds(5))
        Task { await refreshEngineStatus() }
    }

    // MARK: Translate selection

    func translateSelection() async {
        guard !isBusy else {
            hud.show("Ya hay una traducción en curso.", style: .info)
            return
        }
        isBusy = true
        defer { isBusy = false }

        do {
            // Reading a selection is harmless (⌘C, clipboard restored), so it works in any app.
            let target = try prepareAccessor(forDraft: false)
            await KeyboardSimulator.waitForModifierRelease()
            let selection = try await target.captureSelection()

            let direction = LanguageDirection.detect(selection.text, native: settings.nativeLanguage, target: settings.targetLanguage)
            selectionPanel.state.onClose = { [weak self] in self?.selectionPanel.close() }
            selectionPanel.onDismiss = { [app = target.app] in app.activate() }
            selectionPanel.show(directionLabel: "\(Self.languageLabel(direction.source)) → \(Self.languageLabel(direction.target))")

            let translator = makeTranslator(from: direction.source, to: direction.target)
            let source = selection.text
            let translation = try await withTimeout(.seconds(45)) { try await translator.translate(source) }
            showSelectionResult(translation, for: selection, in: target)
        } catch {
            if selectionPanel.isVisible {
                selectionPanel.state.phase = .failed(error.localizedDescription)
                selectionPanel.refit()
            } else {
                fail(error)
            }
        }
    }

    private func showSelectionResult(_ translation: DraftTranslation, for selection: SelectionSnapshot, in target: DraftAccessor) {
        let state = selectionPanel.state
        state.phase = .done(translation.text)
        state.canReplace = selection.isEditable
        state.note = translation.failures.first.map { "Con \(translation.engineName ?? "el motor de respaldo"): \($0.engineName) falló." }
        state.onCopy = { [weak self] in
            Clipboard.write(translation.text)
            self?.selectionPanel.close()
            self?.hud.show("Traducción copiada.", style: .success)
        }
        state.onReplace = { [weak self] in
            guard let self else { return }
            selectionPanel.close()
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                do {
                    try await target.replaceSelection(selection, with: translation.text)
                    self.hud.show("Selección reemplazada por la traducción.", style: .success)
                } catch {
                    self.fail(error)
                }
            }
        }
        selectionPanel.refit()
    }

    // MARK: Improve prompt

    /// Where the prompt came from, so "Reemplazar" writes back to exactly that place.
    private enum PromptSource {
        case selection(SelectionSnapshot)
        case field(DraftSnapshot)

        var text: String {
            switch self {
            case let .selection(selection): selection.text
            case let .field(field): field.text
            }
        }
    }

    func improvePrompt() async {
        guard !isBusy else {
            hud.show("Ya hay una traducción en curso.", style: .info)
            return
        }
        isBusy = true
        defer { isBusy = false }

        do {
            let target = try prepareAccessor(forDraft: false)
            await KeyboardSimulator.waitForModifierRelease()
            let isTerminal = AppScope.isTerminal(target.app.bundleIdentifier)
            let source = try await capturePrompt(in: target, isTerminal: isTerminal)

            let options = PromptOptions(profile: settings.promptProfile, toEnglish: settings.promptToEnglish, glossary: settings.style.glossary)
            selectionPanel.state.onClose = { [weak self] in self?.selectionPanel.close() }
            selectionPanel.onDismiss = { [app = target.app] in app.activate() }
            selectionPanel.show(directionLabel: options.profile.title + (options.toEnglish ? " · en inglés" : ""), width: 560)

            let improver = makePromptImprover(options)
            let text = source.text
            let result = try await withTimeout(.seconds(60)) { try await improver.improve(text) }
            showPromptResult(result, source: source, in: target, canReplace: !isTerminal)
        } catch {
            if selectionPanel.isVisible {
                selectionPanel.state.phase = .failed(error.localizedDescription)
                selectionPanel.refit()
            } else {
                fail(error)
            }
        }
    }

    /// The selection if there is one, otherwise the whole focused field.
    private func capturePrompt(in target: DraftAccessor, isTerminal: Bool) async throws -> PromptSource {
        let element = await target.focusedElement()
        if let range = element?.selectedRange, element?.isTextInput == true {
            if range.length > 0 { return .selection(try await target.captureSelection()) }
        } else if let selection = try? await target.captureSelection() {
            return .selection(selection)
        }
        guard !isTerminal else { throw AppError.selectPromptInTerminal }
        let field = try await target.capture()
        guard field.text.count <= 8_000 else {
            await target.deselectIfStillFrontmost(after: field)
            throw AppError.promptTooLong
        }
        return .field(field)
    }

    private func makePromptImprover(_ options: PromptOptions) -> PromptImprover {
        var rewriters: [any TextRewriter] = []
        switch settings.engine {
        case .appleIntelligence:
            rewriters.append(AppleIntelligenceEngine(style: settings.style))
        case .ollama:
            rewriters.append(OllamaEngine(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel, style: settings.style))
        case .appleTranslation:
            break
        }
        // Prompts are written in English; translating from my language is the fallback.
        let english = TranslationLanguage.englishUS
        let fallback = settings.nativeLanguage.isSameLanguage(as: english) ? nil
            : DraftTranslator(engines: [appleTranslation], source: draftSource, target: english.language, engineTimeout: .seconds(20))
        return PromptImprover(rewriters: rewriters, fallback: fallback, options: options, timeout: .seconds(45))
    }

    private func showPromptResult(_ result: PromptImprovement, source: PromptSource, in target: DraftAccessor, canReplace: Bool) {
        let state = selectionPanel.state
        state.phase = .done(result.text)
        state.canReplace = canReplace && {
            if case let .selection(selection) = source { return selection.isEditable }
            return true
        }()
        if result.translatedOnly {
            state.note = "Solo traducido con \(result.engineName): \(result.failures.first?.message ?? "no hay motor LLM").".replacingOccurrences(of: "..", with: ".")
        } else {
            state.note = result.failures.first.map { "Con \(result.engineName): \($0.engineName) falló." }
        }
        state.onCopy = { [weak self] in
            Clipboard.write(result.text)
            self?.selectionPanel.close()
            self?.hud.show("Prompt copiado.", style: .success)
        }
        state.onReplace = { [weak self] in
            guard let self else { return }
            selectionPanel.close()
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                do {
                    switch source {
                    case let .selection(selection):
                        try await target.replaceSelection(selection, with: result.text)
                    case let .field(field):
                        try await target.replace(field, with: result.text)
                        self.lastTranslation = LastTranslation(
                            identity: field.identity,
                            appName: target.app.localizedName ?? "",
                            original: field.text,
                            translated: result.text,
                            method: field.method
                        )
                    }
                    self.hud.show("Prompt reemplazado.", style: .success)
                } catch {
                    self.fail(error)
                }
            }
        }
        selectionPanel.refit()
    }

    private static func languageLabel(_ language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else { return "?" }
        return TranslationLanguage(code).languageName()
    }

    func copyOriginal() {
        guard let last = lastTranslation else { return }
        Clipboard.write(last.original)
        hud.show("Texto original copiado al portapapeles.", style: .success)
    }

    // MARK: Diagnostics

    func runDiagnostics(writeTest: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        for remaining in stride(from: 3, through: 1, by: -1) {
            hud.show("Diagnóstico en \(remaining) s: deja el cursor en el cuadro de mensaje de Discord.", style: .progress)
            try? await Task.sleep(for: .seconds(1))
        }
        hud.show("Analizando el campo activo…", style: .progress)
        let report = await Diagnostics.run(writeTest: writeTest, settings: settings)
        hud.hide()

        diagnosticsReport = report
        diagnosticsFile = Diagnostics.save(report)
        windows.show(id: "diagnostics", title: "Diagnóstico de VibeTranslator") { DiagnosticsView(model: self) }
    }

    // MARK: Permissions, languages, hot keys

    func refreshEngineStatus() async {
        appleIntelligenceStatus = AppleIntelligenceEngine.statusText
        do {
            ollamaModels = try await OllamaEngine.installedModels(baseURL: settings.ollamaBaseURL)
            ollamaStatus = ollamaModels.isEmpty ? "Ollama está en marcha pero no tiene modelos descargados." : nil
            if settings.ollamaModel.isEmpty, let local = ollamaModels.first(where: { !$0.isCloud }) {
                settings.ollamaModel = local.name
            }
        } catch {
            ollamaModels = []
            ollamaStatus = error.localizedDescription
        }
    }

    func refreshLanguageStatus() async {
        languageStatus = await AppleTranslationEngine.availability(from: draftSource, to: draftTarget)
    }

    var languageStatusText: String {
        switch languageStatus {
        case .installed: "Instalados"
        case .supported: "Pendientes de descarga"
        case .unsupported: "No disponibles"
        case nil: "Comprobando…"
        @unknown default: "Desconocido"
        }
    }

    func refreshTrust() {
        isTrusted = Accessibility.isTrusted
    }

    func suspendHotKeys() {
        hotKeys.unregisterAll()
    }

    func resumeHotKeys() {
        registerHotKeys()
    }

    func showLanguageSetup() {
        windows.show(id: "languages", title: "Idiomas de traducción") { LanguageSetupView(model: self) }
    }

    private func registerHotKeys() {
        var failed: [String] = []
        if !hotKeys.register(settings.translateShortcut, for: .translate) {
            failed.append("traducir (\(settings.translateShortcut?.displayString ?? ""))")
        }
        if !hotKeys.register(settings.restoreShortcut, for: .restore) {
            failed.append("restaurar (\(settings.restoreShortcut?.displayString ?? ""))")
        }
        if !hotKeys.register(settings.selectionShortcut, for: .translateSelection) {
            failed.append("traducir selección (\(settings.selectionShortcut?.displayString ?? ""))")
        }
        if !hotKeys.register(settings.promptShortcut, for: .improvePrompt) {
            failed.append("mejorar prompt (\(settings.promptShortcut?.displayString ?? ""))")
        }
        hotKeyProblem = failed.isEmpty ? nil : "No se pudo registrar el atajo de \(failed.joined(separator: " y ")); probablemente lo usa otra app."
    }

    /// `forDraft`: whole-draft actions (translate, restore), which only run where the app
    /// scope allows and never in terminals. Selection and prompt actions work anywhere.
    private func prepareAccessor(forDraft: Bool = true) throws -> DraftAccessor {
        refreshTrust()
        guard isTrusted else {
            Accessibility.requestTrust()
            startTrustPolling()
            throw AppError.accessibilityDenied
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw AppError.noFrontmostApp }
        if forDraft {
            guard !AppScope.isTerminal(app.bundleIdentifier) else { throw AppError.draftInTerminal }
            guard settings.appScope.allows(app.bundleIdentifier) else {
                throw AppError.appNotAllowed(app.localizedName ?? "esta app")
            }
        }
        return DraftAccessor(app: app, mode: settings.accessMode)
    }

    private func startTrustPolling() {
        guard trustPolling == nil else { return }
        trustPolling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                self.refreshTrust()
                if self.isTrusted {
                    self.trustPolling = nil
                    return
                }
            }
        }
    }

    private func fail(_ error: Error, hint: String? = nil) {
        let message = [error.localizedDescription, hint].compactMap(\.self).joined(separator: " ")
        log.error("\(message, privacy: .public)")
        NSSound.beep()
        hud.show(message, style: .error)
        if case TranslationEngineError.languagesNotInstalled = error {
            Task { await refreshLanguageStatus() }
            showLanguageSetup()
        }
    }
}
