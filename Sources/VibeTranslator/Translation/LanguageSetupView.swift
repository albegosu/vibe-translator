import SwiftUI
import Translation

/// Apple only lets a SwiftUI-hosted session ask the user to download language packs.
struct LanguageSetupView: View {
    let model: AppModel

    @State private var configuration: TranslationSession.Configuration?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Idiomas de traducción").font(.title3.bold())
            Text("Apple Translation traduce en el propio Mac y es el motor de respaldo. Necesita descargar una vez los idiomas que uses; después funciona sin conexión.")
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent(model.languagePairLabel, value: model.languageStatusText)

            HStack {
                Button("Descargar idiomas") {
                    message = nil
                    if configuration == nil {
                        configuration = TranslationSession.Configuration(source: model.draftSource, target: model.draftTarget)
                    } else {
                        configuration?.invalidate()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.languageStatus == .installed)

                Button("Ajustes de Idioma y región") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440)
        .translationTask(configuration) { session in
            // The framework hands this session to this closure only; nothing else touches it.
            nonisolated(unsafe) let session = session
            do {
                try await session.prepareTranslation()
                message = "Idiomas listos."
            } catch {
                message = "No se completó la descarga: \(error.localizedDescription)"
            }
            await model.refreshLanguageStatus()
        }
        .task { await model.refreshLanguageStatus() }
    }
}
