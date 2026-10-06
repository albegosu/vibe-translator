import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press the new combination. Esc cancels; the ✕ button clears it.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .frame(minWidth: 110)
                    .foregroundStyle(rejected ? .red : .primary)
            }
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Quitar atajo")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return rejected ? String(localized: "Usa ⌃, ⌥ o ⌘") : String(localized: "Pulsa el atajo…") }
        return shortcut?.displayString ?? String(localized: "Sin atajo")
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        rejected = false
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let candidate = Shortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)
            guard candidate.isValidGlobalShortcut else {
                rejected = true
                NSSound.beep()
                return nil
            }
            shortcut = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        rejected = false
        onRecordingChange(false)
    }
}
