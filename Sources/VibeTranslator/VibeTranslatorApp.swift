import AppKit
import SwiftUI

@main
struct VibeTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: AppModel.shared)
        } label: {
            MenuBarIcon(model: AppModel.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
        }
    }
}

private struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.isBusy ? "ellipsis.bubble.fill" : "character.bubble")
    }
}

private struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Button("Traducir borrador al inglés" + shortcutSuffix(model.settings.translateShortcut)) {
            Task { await model.translateDraft() }
        }
        .disabled(model.isBusy)

        Button("Restaurar original" + shortcutSuffix(model.settings.restoreShortcut)) {
            Task { await model.restoreOriginal() }
        }
        .disabled(model.isBusy || model.lastTranslation == nil || model.lastTranslation?.restored == true)

        Button("Traducir selección" + shortcutSuffix(model.settings.selectionShortcut)) {
            Task { await model.translateSelection() }
        }
        .disabled(model.isBusy)

        Button("Copiar original al portapapeles") {
            model.copyOriginal()
        }
        .disabled(model.lastTranslation == nil)

        Divider()

        if !model.isTrusted {
            Button("⚠︎ Conceder permiso de Accesibilidad…") {
                Accessibility.requestTrust()
                Accessibility.openPrivacySettings()
            }
        }
        if model.languageStatus != .installed {
            Button("⚠︎ Idiomas español → inglés: \(model.languageStatusText.lowercased())…") {
                model.showLanguageSetup()
            }
        }
        if let problem = model.hotKeyProblem {
            Text("⚠︎ \(problem)")
        }
        if let engineWarning {
            Text("⚠︎ \(engineWarning) Se usará Apple Translation.")
        }

        Menu("Validación técnica") {
            Button("Diagnosticar campo activo (en 3 s)") {
                Task { await model.runDiagnostics(writeTest: false) }
            }
            Button("Diagnosticar y probar escritura (borrador vacío, en 3 s)") {
                Task { await model.runDiagnostics(writeTest: true) }
            }
        }
        .disabled(model.isBusy)

        Button("Ajustes…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Salir de VibeTranslator") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Why the chosen LLM can't run right now, if it can't.
    private var engineWarning: String? {
        switch model.settings.engine {
        case .appleIntelligence:
            model.appleIntelligenceStatus == "Disponible" ? nil : model.appleIntelligenceStatus
        case .ollama:
            model.ollamaStatus ?? (model.settings.ollamaModel.isEmpty ? "No hay modelo de Ollama elegido." : nil)
        case .appleTranslation:
            nil
        }
    }

    private func shortcutSuffix(_ shortcut: Shortcut?) -> String {
        shortcut.map { "  (\($0.displayString))" } ?? ""
    }
}
