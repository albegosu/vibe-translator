// Prints every type on the general pasteboard, read-only. Useful to see how an editor
// serializes rich content (e.g. Discord mentions and custom emoji) when you copy it.
//
//   1. In the app, select the content and press ⌘C.
//   2. swift scripts/inspect-pasteboard.swift
//
// Chromium/Electron apps keep web-only formats (like Slate's `application/x-slate-fragment`)
// inside `org.chromium.web-custom-data`, which is decoded here.
import AppKit

let limit = 2_000

func show(_ text: String) -> String {
    text.count > limit ? String(text.prefix(limit)) + "… (\(text.count) chars)" : text
}

/// Chromium's custom data is a Pickle: header, count, then UTF-16 (type, value) pairs.
func decodeChromiumCustomData(_ data: Data) -> [(String, String)] {
    var offset = 4 // pickle payload size
    func uint32() -> Int? {
        guard offset + 4 <= data.count else { return nil }
        defer { offset += 4 }
        return Int(data[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }
    func string16() -> String? {
        guard let length = uint32(), offset + length * 2 <= data.count else { return nil }
        let bytes = data[offset..<offset + length * 2]
        offset += (length * 2 + 3) & ~3 // 4-byte alignment
        return String(data: bytes, encoding: .utf16LittleEndian)
    }
    guard let count = uint32(), count < 1_000 else { return [] }
    var pairs: [(String, String)] = []
    for _ in 0..<count {
        guard let type = string16(), let value = string16() else { break }
        pairs.append((type, value))
    }
    return pairs
}

/// Slate fragments are `btoa(encodeURIComponent(JSON))`.
func decodeSlateFragment(_ value: String) -> String? {
    guard let data = Data(base64Encoded: value),
          let encoded = String(data: data, encoding: .utf8),
          let json = encoded.removingPercentEncoding,
          let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
          let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    else { return nil }
    return String(decoding: pretty, as: UTF8.self)
}

let pasteboard = NSPasteboard.general
let items = pasteboard.pasteboardItems ?? []
print("Pasteboard change count \(pasteboard.changeCount), \(items.count) item(s)")

for (index, item) in items.enumerated() {
    print("\n=== Item \(index + 1)")
    for type in item.types {
        let data = item.data(forType: type) ?? Data()
        print("\n--- \(type.rawValue) (\(data.count) bytes)")
        if type.rawValue == "org.chromium.web-custom-data" {
            for (customType, value) in decodeChromiumCustomData(data) {
                print("  [\(customType)]")
                print(show(customType == "application/x-slate-fragment" ? decodeSlateFragment(value) ?? value : value))
            }
        } else if let text = item.string(forType: type) {
            print(show(text))
        }
    }
}
