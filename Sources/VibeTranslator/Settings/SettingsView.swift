import SwiftUI
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
                Picker("Método", selection: $settings.accessMode) {
                    ForEach(AccessMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Traducir el borrador solo en Discord", isOn: $settings.onlyInDiscord)
            } header: {
                Text("Acceso al borrador")
            } footer: {
                Footnote("Automático usa el portapapeles en apps como Discord y Accesibilidad en campos nativos. Tu portapapeles siempre se restaura.")
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
        .frame(width: SettingsView.width, height: 500)
    }

    private func recordingChanged(_ isRecording: Bool) {
        if isRecording { model.suspendHotKeys() } else { model.resumeHotKeys() }
    }
}

struct TranslationSettingsTab: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings

        Form {
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
                                    Text(settings.ollamaModel.isEmpty ? "Ninguno" : settings.ollamaModel).tag(settings.ollamaModel)
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
                    TextField("Instrucciones extra", text: $settings.extraInstructions, prompt: Text("Usa ortografía británica…"), axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Estilo")
                } footer: {
                    Footnote("El tono y las instrucciones se aplican en la siguiente traducción.")
                }
            }

            Section {
                LabeledContent("Español ↔ Inglés") {
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
        .frame(width: SettingsView.width, height: 690)
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
                Footnote(profileDescription(settings.promptProfile))
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
        case .agentTask: "Estructura el prompt en Objetivo, Contexto, Requisitos y Cuándo está terminado."
        case .concise: "Lo deja en uno o dos párrafos claros y directos."
        }
    }
}

/// An icon and a sentence, with the icons in one column whatever their width.
private struct InfoRow: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
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
    let text: LocalizedStringKey

    init(_ text: String) {
        self.text = LocalizedStringKey(text)
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
