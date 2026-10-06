import AppKit
import ApplicationServices
import VibeTranslatorCore

/// First technical validation: what the focused editor exposes through Accessibility,
/// what ⌘A ⌘C returns, and (optionally, only on an empty draft) whether AX writes and
/// pastes actually reach the editor's own model.
@MainActor
enum Diagnostics {
    static func run(writeTest: Bool, settings: AppSettings) async -> String {
        var report = Report()

        report.section("Sistema")
        report.line("Fecha", Date().formatted(.iso8601))
        report.line("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
        report.line("VibeTranslator", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "desarrollo")
        report.line("Permiso de Accesibilidad", Accessibility.isTrusted ? "concedido" : "NO concedido")
        let languages = await AppleTranslationEngine.availability(from: AppModel.source, to: AppModel.target)
        report.line("Apple Translation es→en", "\(languages)")
        report.line("Método configurado", settings.accessMode.title)
        report.line("Motor configurado", settings.engine.title)
        report.line("Apple Intelligence", AppleIntelligenceEngine.statusText)
        if let models = try? await OllamaEngine.installedModels(baseURL: settings.ollamaBaseURL) {
            report.line("Ollama", models.isEmpty ? "en marcha, sin modelos" : models.map { $0.isCloud ? "\($0.name) (nube)" : $0.name }.joined(separator: ", "))
        } else {
            report.line("Ollama", "no responde en \(settings.ollamaBaseURL.absoluteString)")
        }

        guard Accessibility.isTrusted else {
            report.note("Sin permiso de Accesibilidad no se puede analizar el campo.")
            return report.text
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            report.note("No hay ninguna app activa.")
            return report.text
        }

        let accessor = DraftAccessor(app: app, mode: settings.accessMode)
        report.section("App activa")
        report.line("Nombre", app.localizedName ?? "—")
        report.line("Bundle ID", app.bundleIdentifier ?? "—")
        report.line("Versión", app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "—")
        report.line("Electron", accessor.isElectron ? "sí" : "no")
        if let result = accessor.manualAccessibilityResult {
            report.line("AXManualAccessibility ← true", result.name)
        }
        report.line("Ventana", accessor.focusedWindowTitle ?? "—")

        report.section("Elemento con foco (Accesibilidad)")
        let element = await accessor.focusedElement()
        let axValue = element?.stringValue
        if let element {
            report.line("AXRole", element.role ?? "—")
            report.line("AXSubrole", element.string(kAXSubroleAttribute) ?? "—")
            report.line("AXRoleDescription", element.string(kAXRoleDescriptionAttribute) ?? "—")
            report.line("AXDOMIdentifier", element.string("AXDOMIdentifier") ?? "—")
            report.line("AXDOMClassList", (element.attribute("AXDOMClassList") as? [String])?.joined(separator: " ") ?? "—")
            report.line("Se considera campo de texto", element.isTextInput ? "sí" : "no")
            report.line("AXValue", axValue.map { "\($0.count) caracteres" } ?? "no disponible")
            if let axValue {
                report.line("AXValue (vista previa)", preview(axValue))
                report.line("Contiene U+FFFC (objetos incrustados)", axValue.contains("\u{FFFC}") ? "sí" : "no")
            }
            report.line("AXSelectedTextRange", element.selectedRange.map { "\($0.location)+\($0.length)" } ?? "—")
            report.line("Escribible AXValue", element.isSettable(kAXValueAttribute) ? "sí" : "no")
            report.line("Escribible AXSelectedText", element.isSettable(kAXSelectedTextAttribute) ? "sí" : "no")
            report.line("Escribible AXSelectedTextRange", element.isSettable(kAXSelectedTextRangeAttribute) ? "sí" : "no")
            report.line("Atributos", element.attributeNames.joined(separator: ", "))
            report.line("Atributos parametrizados", element.parameterizedAttributeNames.joined(separator: ", "))
        } else {
            report.line("Elemento con foco", "no disponible")
        }

        report.section("Lectura por portapapeles (⌘A ⌘C, portapapeles restaurado)")
        do {
            let copied = try await accessor.copyAll()
            await KeyboardSimulator.collapseSelectionToEnd()
            report.line("Texto copiado", "\(copied.count) caracteres")
            report.line("Vista previa", preview(copied))
            if let axValue {
                report.line("Igual que AXValue", DraftText.isSame(copied, axValue) ? "sí" : "no")
            }
        } catch {
            report.line("Resultado", error.localizedDescription)
        }

        if writeTest {
            await runWriteTest(accessor: accessor, element: element, into: &report)
        }

        report.section("Conclusión")
        report.line("Automático usaría", automaticChoice(accessor: accessor, element: element))
        return report.text
    }

    private static func runWriteTest(accessor: DraftAccessor, element: AXUIElement?, into report: inout Report) async {
        report.section("Prueba de escritura")
        let current = (try? await accessor.copyAll()) ?? element?.stringValue ?? ""
        await KeyboardSimulator.collapseSelectionToEnd()
        guard DraftText.normalized(current).isEmpty else {
            report.note("Omitida: el borrador no está vacío. Vacíalo y repite para probar la escritura.")
            return
        }

        // A) Accessibility: does replacing the selection reach the editor's model?
        if let element, element.isTextInput {
            let marker = "VibeTranslator prueba AX"
            let result = element.set(kAXSelectedTextAttribute, marker as CFString)
            try? await Task.sleep(for: .milliseconds(200))
            let modelText = try? await accessor.copyAll()
            report.line("A. AXSelectedText ← texto", result.name)
            report.line("A. AXValue después", preview(element.stringValue ?? "—"))
            report.line("A. Lo que copia el editor después", preview(modelText ?? "—"))
            report.line("A. Escritura AX llega al editor", modelText.map { DraftText.isSame($0, marker) } == true ? "SÍ" : "NO")
            await clearDraft(accessor: accessor, element: element, copied: modelText)
        } else {
            report.line("A. Escritura AX", "omitida: no hay campo de texto accesible")
        }

        // B) Clipboard paste, multi-line, as the translation would be written.
        let marker = "VibeTranslator prueba pegado\nsegunda línea"
        let saved = ClipboardSnapshot()
        let ours = Clipboard.writeTransient(marker)
        await KeyboardSimulator.command("v")
        try? await Task.sleep(for: .milliseconds(400))
        saved.restore(ifChangeCountIs: ours)
        let pasted = try? await accessor.copyAll()
        report.line("B. Lo que copia el editor tras ⌘V", preview(pasted ?? "—"))
        report.line("B. Pegado multilínea correcto", pasted.map { DraftText.isSame($0, marker) } == true ? "SÍ" : "NO")
        if let element {
            report.line("B. AXValue tras ⌘V", preview(element.stringValue ?? "—"))
        }
        await clearDraft(accessor: accessor, element: element, copied: pasted)
    }

    /// Empties the draft only if the test left something in it: Backspace on an empty
    /// Discord composer can cancel a pending reply.
    private static func clearDraft(accessor: DraftAccessor, element: AXUIElement?, copied: String?) async {
        let leftover = copied ?? element?.stringValue ?? ""
        guard !DraftText.normalized(leftover).isEmpty, (try? accessor.ensureFrontmost()) != nil else { return }
        await KeyboardSimulator.command("a")
        await KeyboardSimulator.deleteBackward()
    }

    private static func automaticChoice(accessor: DraftAccessor, element: AXUIElement?) -> String {
        if accessor.isElectron { return "Portapapeles (app Electron: el editor gestiona su propio modelo)" }
        guard let element, let value = element.stringValue else { return "Portapapeles (sin AXValue)" }
        if value.contains("\u{FFFC}") { return "Portapapeles (AXValue no representa objetos incrustados)" }
        if element.isSettable(kAXSelectedTextAttribute) || element.isSettable(kAXValueAttribute) { return "Accesibilidad" }
        return "Portapapeles (campo no escribible por AX)"
    }

    private static func preview(_ text: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: "⏎")
        return "«" + (flattened.count > 160 ? String(flattened.prefix(160)) + "…" : flattened) + "»"
    }

    static func save(_ report: String) -> URL? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/VibeTranslator", isDirectory: true)
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let file = folder.appendingPathComponent("diagnostico-\(stamp).txt")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try report.write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            return nil
        }
    }

    struct Report {
        private(set) var text = ""

        mutating func section(_ title: String) {
            text += (text.isEmpty ? "" : "\n") + "## \(title)\n"
        }

        mutating func line(_ label: String, _ value: String) {
            text += "- \(label): \(value)\n"
        }

        mutating func note(_ message: String) {
            text += "  \(message)\n"
        }
    }
}
