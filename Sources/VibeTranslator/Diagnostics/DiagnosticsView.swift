import AppKit
import SwiftUI

struct DiagnosticsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(model.diagnosticsReport ?? "Sin diagnóstico todavía.")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                if let file = model.diagnosticsFile {
                    Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
                Spacer()
                Button("Copiar informe") {
                    if let report = model.diagnosticsReport { Clipboard.write(report) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 640, height: 560)
    }
}
