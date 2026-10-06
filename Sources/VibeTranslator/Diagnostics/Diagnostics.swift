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

        report.section("System")
        report.line("Date", Date().formatted(.iso8601))
        report.line("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
        report.line("VibeTranslator", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")
        report.line("Accessibility permission", Accessibility.isTrusted ? "granted" : "NOT granted")
        let languages = await AppleTranslationEngine.availability(from: settings.nativeLanguage.language, to: settings.targetLanguage.language)
        report.line("Languages", "\(settings.nativeLanguage.id) → \(settings.targetLanguage.id)")
        report.line("Apple Translation", "\(languages)")
        report.line("Access method", settings.accessMode.rawValue)
        report.line("Engine", settings.engine.rawValue)
        report.line("Apple Intelligence", AppleIntelligenceEngine.statusText)
        if let models = try? await OllamaEngine.installedModels(baseURL: settings.ollamaBaseURL) {
            report.line("Ollama", models.isEmpty ? "running, no models" : models.map { $0.isCloud ? "\($0.name) (cloud)" : $0.name }.joined(separator: ", "))
        } else {
            report.line("Ollama", "not responding at \(settings.ollamaBaseURL.absoluteString)")
        }

        guard Accessibility.isTrusted else {
            report.note("Without the Accessibility permission the field can't be inspected.")
            return report.text
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            report.note("No frontmost app.")
            return report.text
        }

        let accessor = DraftAccessor(app: app, mode: settings.accessMode)
        report.section("Frontmost app")
        report.line("Name", app.localizedName ?? "—")
        report.line("Bundle ID", app.bundleIdentifier ?? "—")
        report.line("Version", app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "—")
        report.line("Electron", accessor.isElectron ? "yes" : "no")
        if let result = accessor.manualAccessibilityResult {
            report.line("AXManualAccessibility ← true", result.name)
        }
        report.line("Window", accessor.focusedWindowTitle ?? "—")

        report.section("Focused element (Accessibility)")
        let element = await accessor.focusedElement()
        let axValue = element?.stringValue
        if let element {
            report.line("AXRole", element.role ?? "—")
            report.line("AXSubrole", element.string(kAXSubroleAttribute) ?? "—")
            report.line("AXRoleDescription", element.string(kAXRoleDescriptionAttribute) ?? "—")
            report.line("AXDOMIdentifier", element.string("AXDOMIdentifier") ?? "—")
            report.line("AXDOMClassList", (element.attribute("AXDOMClassList") as? [String])?.joined(separator: " ") ?? "—")
            report.line("Treated as a text field", element.isTextInput ? "yes" : "no")
            report.line("AXValue", axValue.map { "\($0.count) characters" } ?? "not available")
            if let axValue {
                report.line("AXValue (vista previa)", preview(axValue))
                report.line("Contains U+FFFC (embedded objects)", axValue.contains("\u{FFFC}") ? "yes" : "no")
            }
            report.line("AXSelectedTextRange", element.selectedRange.map { "\($0.location)+\($0.length)" } ?? "—")
            report.line("Writable AXValue", element.isSettable(kAXValueAttribute) ? "yes" : "no")
            report.line("Writable AXSelectedText", element.isSettable(kAXSelectedTextAttribute) ? "yes" : "no")
            report.line("Writable AXSelectedTextRange", element.isSettable(kAXSelectedTextRangeAttribute) ? "yes" : "no")
            report.line("Attributes", element.attributeNames.joined(separator: ", "))
            report.line("Parameterized attributes", element.parameterizedAttributeNames.joined(separator: ", "))
        } else {
            report.line("Focused element", "not available")
        }

        report.section("Clipboard read (⌘A ⌘C, clipboard restored)")
        do {
            let copied = try await accessor.copyAll()
            await KeyboardSimulator.collapseSelectionToEnd()
            report.line("Copied text", "\(copied.count) characters")
            report.line("Preview", preview(copied))
            if let axValue {
                report.line("Same as AXValue", DraftText.isSame(copied, axValue) ? "yes" : "no")
            }
        } catch {
            report.line("Result", error.localizedDescription)
        }

        if writeTest {
            await runWriteTest(accessor: accessor, element: element, into: &report)
        }

        report.section("Conclusion")
        report.line("Automatic would use", automaticChoice(accessor: accessor, element: element))
        return report.text
    }

    private static func runWriteTest(accessor: DraftAccessor, element: AXUIElement?, into report: inout Report) async {
        report.section("Write test")
        let current = (try? await accessor.copyAll()) ?? element?.stringValue ?? ""
        await KeyboardSimulator.collapseSelectionToEnd()
        guard DraftText.normalized(current).isEmpty else {
            report.note("Skipped: the draft isn't empty. Empty it and run again to test writing.")
            return
        }

        // A) Accessibility: does replacing the selection reach the editor's model?
        if let element, element.isTextInput {
            let marker = "VibeTranslator AX test"
            let result = element.set(kAXSelectedTextAttribute, marker as CFString)
            try? await Task.sleep(for: .milliseconds(200))
            let modelText = try? await accessor.copyAll()
            report.line("A. AXSelectedText ← text", result.name)
            report.line("A. AXValue afterwards", preview(element.stringValue ?? "—"))
            report.line("A. What the editor copies afterwards", preview(modelText ?? "—"))
            report.line("A. AX write reaches the editor", modelText.map { DraftText.isSame($0, marker) } == true ? "YES" : "NO")
            await clearDraft(accessor: accessor, element: element, copied: modelText)
        } else {
            report.line("A. AX write", "skipped: no accessible text field")
        }

        // B) Clipboard paste, multi-line, as the translation would be written.
        let marker = "VibeTranslator paste test\nsecond line"
        let saved = ClipboardSnapshot()
        let ours = Clipboard.writeTransient(marker)
        await KeyboardSimulator.command("v")
        try? await Task.sleep(for: .milliseconds(400))
        saved.restore(ifChangeCountIs: ours)
        let pasted = try? await accessor.copyAll()
        report.line("B. What the editor copies after ⌘V", preview(pasted ?? "—"))
        report.line("B. Multi-line paste intact", pasted.map { DraftText.isSame($0, marker) } == true ? "YES" : "NO")
        if let element {
            report.line("B. AXValue after ⌘V", preview(element.stringValue ?? "—"))
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
        if accessor.isElectron { return "Clipboard (Electron app: the editor keeps its own model)" }
        guard let element, let value = element.stringValue else { return "Clipboard (no AXValue)" }
        if value.contains("\u{FFFC}") { return "Clipboard (AXValue can't represent embedded objects)" }
        if element.isSettable(kAXSelectedTextAttribute) || element.isSettable(kAXValueAttribute) { return "Accessibility" }
        return "Clipboard (field not writable through AX)"
    }

    private static func preview(_ text: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: "⏎")
        return "«" + (flattened.count > 160 ? String(flattened.prefix(160)) + "…" : flattened) + "»"
    }

    static func save(_ report: String) -> URL? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/VibeTranslator", isDirectory: true)
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let file = folder.appendingPathComponent("diagnostics-\(stamp).txt")
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
