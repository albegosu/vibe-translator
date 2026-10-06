import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, restricted to ⌃⌥⇧⌘.
    var modifiers: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers).rawValue
    }

    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    static let defaultTranslate = Shortcut(keyCode: UInt16(kVK_ANSI_T), modifiers: [.control, .option])
    static let defaultRestore = Shortcut(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.control, .option])
    static let defaultSelection = Shortcut(keyCode: UInt16(kVK_ANSI_Y), modifiers: [.control, .option])

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// A global shortcut needs ⌃, ⌥ or ⌘; Shift alone would swallow normal typing.
    var isValidGlobalShortcut: Bool {
        !modifierFlags.intersection([.control, .option, .command]).isEmpty
    }

    var displayString: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        let key = KeyboardLayout.specialKeyNames[Int(keyCode)]
            ?? KeyboardLayout.character(for: keyCode)?.uppercased()
            ?? "#\(keyCode)"
        return result + key
    }
}
