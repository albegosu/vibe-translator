import AppKit
import Carbon.HIToolbox

/// Posts synthetic key strokes to the frontmost app. Requires Accessibility trust.
@MainActor
enum KeyboardSimulator {
    private static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// The hotkey's own modifiers are usually still held when it fires; ⌘V sent while
    /// ⌃⌥ are down would arrive as ⌃⌥⌘V. Wait (bounded) until the user lets go.
    static func waitForModifierRelease(timeout: Duration = .milliseconds(1500)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if CGEventSource.flagsState(.combinedSessionState).intersection(relevantModifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    static func command(_ character: Character) async {
        await press(KeyboardLayout.commandKeyCode(for: character), flags: .maskCommand)
    }

    /// Collapses a select-all to the end of the text without changing it.
    static func collapseSelectionToEnd() async {
        await press(CGKeyCode(kVK_RightArrow), flags: [])
    }

    static func deleteBackward() async {
        await press(CGKeyCode(kVK_Delete), flags: [])
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags) async {
        // A private source keeps the user's physical modifier state out of our events.
        let source = CGEventSource(stateID: .privateState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(12))
        }
        try? await Task.sleep(for: .milliseconds(40))
    }
}
