import SwiftUI
import VibeTranslatorCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section("Atajos globales") {
                LabeledContent("Traducir borrador") {
                    ShortcutRecorder(shortcut: $settings.translateShortcut, onRecordingChange: recordingChanged)
                }
                LabeledContent("Restaurar original") {
                    ShortcutRecorder(shortcut: $settings.restoreShortcut, onRecordingChange: recordingChanged)
                }
                LabeledContent("Traducir selección") {
                    ShortcutRecorder(shortcut: $settings.selectionShortcut, onRecordingChange: recordingChanged)
                }
                if let problem = model.hotKeyProblem {
                    Text(problem).foregroundStyle(.red).font(.callout)
                }
            }

            Section {
                LabeledContent("Idiomas", value: "Español → Inglés")
                Picker("Motor", selection: $settings.engine) {
                    ForEach(EngineKind.allCases) { Text($0.title).tag($0) }
                }
                engineStatus(settings.engine)
            } header: {
                Text("Traducción")
            } footer: {
                Text("Si el motor elegido no está disponible, falla o tarda más de 20 s, se traduce con Apple Translation y el aviso lo indica.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.engine.usesStyle {
                Section {
                    Picker("Tono", selection: $settings.tone) {
                        ForEach(TranslationTone.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("No traducir", text: $settings.glossaryText, prompt: Text("PR, deploy, staging…"))
                    LabeledContent("Instrucciones extra") {
                        TextEditor(text: $settings.extraInstructions)
                            .font(.callout)
                            .frame(height: 64)
                            .scrollContentBackground(.hidden)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    }
                } header: {
                    Text("Estilo")
                } footer: {
                    Text("Ejemplo de instrucciones: «Usa ortografía británica», «Llama \"daily\" a la reunión diaria».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.engine == .ollama {
                Section("Ollama") {
                    TextField("Servidor", text: $settings.ollamaURL, prompt: Text(AppSettings.defaultOllamaURL))
                    HStack {
                        Picker("Modelo", selection: $settings.ollamaModel) {
                            if !model.ollamaModels.contains(where: { $0.name == settings.ollamaModel }) {
                                Text(settings.ollamaModel.isEmpty ? "Ninguno" : settings.ollamaModel).tag(settings.ollamaModel)
                            }
                            ForEach(model.ollamaModels) { item in
                                Text(item.isCloud ? "\(item.name)  (nube)" : item.name).tag(item.name)
                            }
                        }
                        Button("Actualizar") { Task { await model.refreshEngineStatus() } }
                    }
                    if settings.ollamaModel.hasSuffix("cloud") {
                        Label("Este modelo se ejecuta en la nube de Ollama: el borrador sale del Mac.", systemImage: "icloud")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    if let status = model.ollamaStatus {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Para un modelo local: `ollama pull <modelo>` en Terminal y pulsa Actualizar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text("Automático usa el portapapeles en apps Electron como Discord (el editor procesa el pegado igual que si pegaras tú) y Accesibilidad en campos nativos. El portapapeles siempre se restaura. «Traducir selección» funciona en cualquier app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permisos") {
                LabeledContent("Accesibilidad") {
                    HStack {
                        Text(model.isTrusted ? "Concedido" : "Pendiente")
                            .foregroundStyle(model.isTrusted ? .green : .orange)
                        if !model.isTrusted {
                            Button("Abrir Ajustes del Sistema") { Accessibility.openPrivacySettings() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize()
        .onAppear { model.refreshTrust() }
        .task { await model.refreshEngineStatus() }
        .onChange(of: settings.ollamaURL) { Task { await model.refreshEngineStatus() } }
    }

    @ViewBuilder
    private func engineStatus(_ engine: EngineKind) -> some View {
        switch engine {
        case .appleIntelligence:
            LabeledContent("Estado", value: model.appleIntelligenceStatus)
        case .ollama:
            LabeledContent("Estado", value: model.ollamaStatus == nil ? "Conectado" : "No disponible")
        case .appleTranslation:
            LabeledContent("Paquetes de idioma") {
                HStack {
                    Text(model.languageStatusText)
                    Button("Gestionar…") { model.showLanguageSetup() }
                }
            }
        }
    }

    private func recordingChanged(_ isRecording: Bool) {
        if isRecording { model.suspendHotKeys() } else { model.resumeHotKeys() }
    }
}
