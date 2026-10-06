import Carbon.HIToolbox
import CoreGraphics

/// Bridges physical key codes and the characters they produce in the user's current layout,
/// so shortcuts display correctly and synthesized ⌘A/⌘C/⌘V hit the right keys on any layout
/// (on AZERTY, the ANSI "A" key is ⌘Q).
enum KeyboardLayout {
    static func character(for keyCode: UInt16, carbonModifiers: UInt32 = 0) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), (carbonModifiers >> 8) & 0xFF,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }

    /// Key that types `character` while ⌘ is held, falling back to the ANSI position.
    static func commandKeyCode(for wanted: Character) -> CGKeyCode {
        let wantedString = String(wanted).lowercased()
        for code in UInt16(0)..<128 where character(for: code, carbonModifiers: UInt32(cmdKey))?.lowercased() == wantedString {
            return code
        }
        return ansiFallback[wanted] ?? 0
    }

    private static let ansiFallback: [Character: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A), "c": CGKeyCode(kVK_ANSI_C), "v": CGKeyCode(kVK_ANSI_V),
    ]

    static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: String(localized: "Espacio"), kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
