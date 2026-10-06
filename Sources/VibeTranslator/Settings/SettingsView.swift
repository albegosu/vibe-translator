import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VibeTranslatorCore

/// Standard macOS settings: toolbar tabs, each a grouped form with a fixed size that
/// scrolls if its content grows (it used to be one form taller than a laptop screen).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            TranslationSettingsTab(model: model)
                .tabItem { Label("Traducción", systemImage: "character.bubble") }
            PromptSettingsTab(model: model)
                .tabItem { Label("Prompts", systemImage: "wand.and.stars") }
        }
        .onAppear { model.refreshTrust() }
        .task { await model.refreshEngineStatus() }
    }

    static let width: CGFloat = 540
}

struct GeneralSettingsTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section("Atajos") {
                LabeledContent("Traducir borrador") {
                    ShortcutRecorder(shortcut: $settings.translateShortcut, onRecordingChange: recordingChanged)
                }
                LabeledContent("Restaurar original") {
                    ShortcutRecorder(shortcut: $settings.restoreShortcut, onRecordingChange: recordingChanged)
                }
                LabeledContent("Traducir selección") {
                    ShortcutRecorder(shortcut: $settings.selectionShortcut, onRecordingChange: recordingChanged)
                }
                LabeledContent("Mejorar prompt") {
                    ShortcutRecorder(shortcut: $settings.promptShortcut, onRecordingChange: recordingChanged)
                }
                if let problem = model.hotKeyProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section {
                Picker("Traducir el borrador en", selection: $settings.appScope.mode) {
                    Text("Todas las apps").tag(AppScopeMode.allApps)
                    Text("Solo en estas apps").tag(AppScopeMode.selectedApps)
                }
                if settings.appScope.mode == .selectedApps {
                    AllowedAppsEditor(apps: $settings.appScope.apps)
                }
                Picker("Método", selection: $settings.accessMode) {
                    ForEach(AccessMode.allCases) { Text($0.title).tag($0) }
                }
                .help("Automático usa el portapapeles en apps como Discord o Slack y Accesibilidad en campos nativos. Tu portapapeles siempre se restaura.")
            } header: {
                Text("Borrador")
            } footer: {
                Footnote("En las terminales nunca se traduce el borrador entero: selecciona el texto y usa «Traducir selección» o «Mejorar prompt».")
            }

            Section("Permisos") {
                LabeledContent("Accesibilidad") {
                    if model.isTrusted {
                        Label("Concedido", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Abrir Ajustes del Sistema…") { Accessibility.openPrivacySettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width, height: 560)
    }

    private func recordingChanged(_ isRecording: Bool) {
        if isRecording { model.suspendHotKeys() } else { model.resumeHotKeys() }
    }
}

/// The apps "translate draft" is limited to, with their icons.
private struct AllowedAppsEditor: View {
    @Binding var apps: [AllowedApp]

    var body: some View {
        if apps.isEmpty {
            Text("Ninguna app: añade al menos una.").foregroundStyle(.orange).font(.callout)
        }
        ForEach(apps) { app in
            HStack(spacing: 8) {
                Image(nsImage: Self.icon(for: app.bundleID))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.name)
                Spacer()
                Button {
                    apps.removeAll { $0.bundleID == app.bundleID }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Quitar \(app.name)")
            }
        }
        Button("Añadir app…", action: addApps)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Añadir")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier, !apps.contains(where: { $0.bundleID == bundleID }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            apps.append(AllowedApp(bundleID: bundleID, name: name))
        }
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct TranslationSettingsTab: View {
    let model: AppModel

    private static let languages = TranslationLanguage.catalog.sorted { $0.displayName(in: .ui) < $1.displayName(in: .ui) }

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section {
                Picker("Mi idioma", selection: $settings.nativeLanguage) {
                    ForEach(Self.languages) { Text($0.displayName(in: .ui)).tag($0) }
                }
                Picker("Traducir a", selection: $settings.targetLanguage) {
                    ForEach(Self.languages) { Text($0.displayName(in: .ui)).tag($0) }
                }
                if !settings.languagesAreValid {
                    Label("Elige dos idiomas distintos.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            } header: {
                Text("Idiomas")
            } footer: {
                Footnote("El borrador va de tu idioma al de destino. Al traducir una selección, lo que esté en tu idioma va al de destino y el resto, a tu idioma.")
            }

            Section {
                Picker("Motor", selection: $settings.engine) {
                    ForEach(EngineKind.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Estado") { engineStatus(settings.engine) }
            } header: {
                Text("Motor")
            } footer: {
                Footnote("Si el motor no está disponible, falla o tarda más de 20 s, se usa Apple Translation y el aviso lo indica.")
            }

            if settings.engine == .ollama {
                Section {
                    TextField("Servidor", text: $settings.ollamaURL, prompt: Text(AppSettings.defaultOllamaURL))
                    LabeledContent("Modelo") {
                        HStack(spacing: 8) {
                            Picker("Modelo", selection: $settings.ollamaModel) {
                                if !model.ollamaModels.contains(where: { $0.name == settings.ollamaModel }) {
                                    Text(settings.ollamaModel.isEmpty ? String(localized: "Ninguno") : settings.ollamaModel).tag(settings.ollamaModel)
                                }
                                ForEach(model.ollamaModels) { item in
                                    Text(item.isCloud ? "\(item.name) (nube)" : item.name).tag(item.name)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button {
                                Task { await model.refreshEngineStatus() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Actualizar la lista de modelos")
                        }
                    }
                    if settings.ollamaModel.hasSuffix("cloud") {
                        Label("Modelo en la nube de Ollama: el texto sale del Mac.", systemImage: "icloud")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                } header: {
                    Text("Ollama")
                } footer: {
                    Footnote("Para un modelo local, ejecuta `ollama pull <modelo>` y pulsa ↻.")
                }
            }

            if settings.engine.usesStyle {
                Section {
                    Picker("Tono", selection: $settings.tone) {
                        ForEach(TranslationTone.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("No traducir", text: $settings.glossaryText, prompt: Text("PR, deploy, staging…"))
                    TextField("Instrucciones extra", text: $settings.extraInstructions, prompt: Text("Llama «daily» a la reunión diaria…"), axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Estilo")
                } footer: {
                    Footnote("El tono y las instrucciones se aplican en la siguiente traducción.")
                }
            }

            Section {
                LabeledContent(model.languagePairLabel) {
                    HStack(spacing: 8) {
                        Text(model.languageStatusText).foregroundStyle(.secondary)
                        Button("Gestionar…") { model.showLanguageSetup() }
                    }
                }
            } header: {
                Text("Apple Translation")
            } footer: {
                Footnote("Paquetes de idioma del traductor de Apple, que es el motor de respaldo.")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width, height: 700)
        .onChange(of: settings.ollamaURL) { Task { await model.refreshEngineStatus() } }
    }

    @ViewBuilder
    private func engineStatus(_ engine: EngineKind) -> some View {
        switch engine {
        case .appleIntelligence:
            Text(model.appleIntelligenceStatus).foregroundStyle(.secondary)
        case .ollama:
            if let problem = model.ollamaStatus {
                Text(problem).foregroundStyle(.orange)
            } else {
                Label("Conectado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .appleTranslation:
            Text(model.languageStatusText).foregroundStyle(.secondary)
        }
    }
}

struct PromptSettingsTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section {
                Picker("Perfil", selection: $settings.promptProfile) {
                    ForEach(PromptProfile.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Escribir el prompt en inglés", isOn: $settings.promptToEnglish)
            } header: {
                Text("Mejorar prompt")
            } footer: {
                Footnote(verbatim: profileDescription(settings.promptProfile))
            }

            Section {
                InfoRow("Nunca toca código, rutas, @menciones, URLs ni variables.", systemImage: "lock")
                InfoRow("Muestra el resultado antes de reemplazar nada.", systemImage: "eye")
                InfoRow("En la terminal, selecciona antes el texto del prompt.", systemImage: "terminal")
            } header: {
                Text("Cómo funciona")
            } footer: {
                Footnote("Usa el motor de la pestaña Traducción; con Apple Translation solo traduce.")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width, height: 340)
    }

    private func profileDescription(_ profile: PromptProfile) -> String {
        switch profile {
        case .agentTask: String(localized: "Estructura el prompt en Objetivo, Contexto, Requisitos y Cuándo está terminado.")
        case .concise: String(localized: "Lo deja en uno o dos párrafos claros y directos.")
        }
    }
}

/// An icon and a sentence, with the icons in one column whatever their width.
private struct InfoRow: View {
    let text: LocalizedStringKey
    let systemImage: String

    init(_ text: LocalizedStringKey, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
        }
    }
}

/// Secondary explanatory text under a settings section.
private struct Footnote: View {
    let text: Text

    init(_ key: LocalizedStringKey) {
        text = Text(key)
    }

    init(verbatim string: String) {
        text = Text(verbatim: string)
    }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
