import Foundation

/// When a selection comes from a web page, and which text the translator should see.
///
/// Browsers expose `AXSelectedText` as one flat line, so headings, lists and code run
/// together. The copy they put on the pasteboard still has the structure: plain text
/// with block breaks, and HTML. Electron apps are left alone — their plain-text copy
/// is what keeps mentions and custom emoji intact.
public enum WebSelection: Sendable {
    /// `isNativeTextField` is a text field that is not inside a web area (an address bar,
    /// TextEdit). A contenteditable on a page is inside the web area and is structured.
    public static func shouldStructure(
        isElectron: Bool,
        isBrowser: Bool,
        isInsideWebArea: Bool,
        isNativeTextField: Bool
    ) -> Bool {
        if isElectron { return false }
        if isInsideWebArea { return true }
        if isNativeTextField { return false }
        return isBrowser
    }

    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        if browserPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) { return true }
        return browserIdentifiers.contains(bundleIdentifier)
    }

    /// Text to translate. HTML wins when it still has the blocks; a conversion that
    /// collapses a multi-line plain copy is discarded.
    public static func translationSource(plain: String, html: String?) -> String {
        guard let html, let structured = StructuredHTML.plainText(from: html) else { return plain }
        // A trailing newline on the plain copy is not structure. Ignore it before deciding
        // that the HTML conversion threw the breaks away.
        let plainHasBreaks = plain.trimmingCharacters(in: .whitespacesAndNewlines).contains("\n")
        if plainHasBreaks, !structured.contains("\n") { return plain }
        return restoringTaskMarkers(in: structured, from: plain)
    }

    /// The plain copy often still has one `- [ ]` per task when the HTML serializer
    /// kept the marker only on the first row. Put those markers back onto the matching
    /// lines without giving up the code spans the HTML conversion recovered.
    static func restoringTaskMarkers(in structured: String, from plain: String) -> String {
        let tasks = taskLines(in: plain)
        guard tasks.count > taskLines(in: structured).count else { return structured }
        var pending = tasks
        let lines = structured.components(separatedBy: "\n").map { line -> String in
            let body = normalizedTaskBody(line)
            guard let index = pending.firstIndex(where: { $0.body == body }) else { return line }
            let task = pending.remove(at: index)
            if taskPrefix(in: line) != nil { return line }
            var text = line
            if let bullet = text.range(of: #"^[ \t]*[-*+][ \t]+"#, options: .regularExpression) {
                text.removeSubrange(bullet)
            }
            return task.indent + (task.checked ? "- [x] " : "- [ ] ") + text.trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
    }

    private struct TaskLine {
        var checked: Bool
        var indent: String
        var body: String
    }

    private static func taskLines(in text: String) -> [TaskLine] {
        text.components(separatedBy: "\n").compactMap { line in
            guard let prefix = taskPrefix(in: line) else { return nil }
            let checked = prefix.contains("[x]") || prefix.contains("[X]")
            let indent = String(prefix.prefix { $0 == " " || $0 == "\t" })
            let body = normalizedTaskBody(String(line.dropFirst(prefix.count)))
            guard !body.isEmpty else { return nil }
            return TaskLine(checked: checked, indent: indent, body: body)
        }
    }

    private static func taskPrefix(in line: String) -> String? {
        guard let range = line.range(of: #"^[ \t]*[-*+][ \t]+\[[ xX]\][ \t]+"#, options: .regularExpression) else { return nil }
        return String(line[..<range.upperBound])
    }

    private static func normalizedTaskBody(_ line: String) -> String {
        var text = line
        if let prefix = taskPrefix(in: text) {
            text.removeFirst(prefix.count)
        }
        return text
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static let browserPrefixes = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "org.mozilla.firefox",
        "company.thebrowser.",
    ]

    private static let browserIdentifiers: Set<String> = [
        "org.mozilla.nightly",
        "org.mozilla.librewolf",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS",
        "app.zen-browser.zen",
        "com.duckduckgo.macos.browser",
        "com.sigmaos.sigmaos.macos",
        "org.waterfoxproject.waterfox",
    ]
}

/// Plain text rebuilt from a browser HTML selection.
///
/// Headings and paragraphs get their own lines, list items keep `- ` / `- [ ]` / `- [x]`
/// (or `1. `), and `<code>` / `<pre>` become backtick spans and fenced blocks so
/// `DraftMarkup` can protect them. A table becomes one line per row. Scripts, styles
/// and images contribute nothing. Tags outside this set only contribute their text,
/// except `div` and the other block containers, which break lines — without that,
/// pages that wrap every block in a `div` would flatten again.
public enum StructuredHTML {
    /// `nil` when the fragment has no readable text, so the caller can keep the plain copy.
    public static func plainText(from html: String) -> String? {
        guard !html.isEmpty, html.count <= 500_000 else { return nil }
        var parser = Parser(fragment(of: html))
        let text = parser.parse()
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard DraftText.hasLetters(text) else { return nil }
        return text
    }

    /// Browsers wrap the real selection in `StartFragment` / `EndFragment`. Everything
    /// outside that (the document chrome) is not part of what the user selected.
    static func fragment(of html: String) -> String {
        guard
            let start = html.range(of: "<!--StartFragment-->", options: .caseInsensitive),
            let end = html.range(of: "<!--EndFragment-->", options: .caseInsensitive),
            start.upperBound <= end.lowerBound
        else { return html }
        return String(html[start.upperBound..<end.lowerBound])
    }
}

private struct Parser {
    private let html: String
    private var index: String.Index
    private var lines: [String] = []
    private var line = ""
    private var pendingPrefix: String?
    private var lists: [List] = []
    private var skipStack: [String] = []
    private var inPre = false
    private var preText = ""
    private var codeDepth = 0
    private var codeText = ""
    private var inRow = false
    private var rowCells = 0
    private var anchors: [Anchor] = []
    /// One entry per open `<li>`. The string is the checkbox marker to repeat on every
    /// line of that item (`nil` for an ordinary bullet). Chrome often serializes a whole
    /// task list as one `<li>` with a `<br>` between rows, so the marker has to travel
    /// with the break or only the first row keeps it.
    private var taskMarkers: [String?] = []
    /// Set by a checkbox that was not inside an `<li>`, so a following `<br>` stays a task.
    private var looseTaskMarker: String?

    private struct List {
        var ordered: Bool
        var index: Int
        /// `ul.contains-task-list`: every item is a checkbox, even if the copy dropped the `<input>`.
        var tasks: Bool
    }

    private struct Anchor {
        var href: String
        var hide: Bool
        var emitted: Bool
    }

    private static let skipped: Set<String> = ["script", "style", "svg", "noscript", "head", "title", "iframe", "object", "canvas", "video", "audio", "template", "math"]
    private static let void: Set<String> = ["br", "hr", "img", "input", "meta", "link", "wbr", "source", "col", "base", "area"]
    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "shy": "", "copy": "©", "reg": "®", "trade": "™",
    ]

    init(_ html: String) {
        self.html = html
        self.index = html.startIndex
    }

    mutating func parse() -> String {
        while index < html.endIndex {
            if html[index] == "<" {
                switch readTag() {
                case let .tag(tag):
                    handle(tag)
                case .ignored:
                    break
                case .notATag:
                    appendText(String(html[index]))
                    index = html.index(after: index)
                }
            } else {
                let start = index
                while index < html.endIndex, html[index] != "<" {
                    index = html.index(after: index)
                }
                appendText(String(html[start..<index]))
            }
        }
        flushLine()
        return lines.joined(separator: "\n")
    }

    private mutating func handle(_ tag: Tag) {
        if !skipStack.isEmpty {
            if tag.closing, tag.name == skipStack.last {
                skipStack.removeLast()
            } else if !tag.closing, Self.skipped.contains(tag.name), !tag.selfClosing {
                skipStack.append(tag.name)
            }
            return
        }
        if !tag.closing, Self.skipped.contains(tag.name) {
            if !tag.selfClosing { skipStack.append(tag.name) }
            return
        }
        if inPre {
            handleInsidePre(tag)
            return
        }
        if codeDepth > 0 {
            handleInsideCode(tag)
            return
        }

        let voids = !tag.closing && (tag.selfClosing || Self.void.contains(tag.name))
        if tag.closing {
            close(tag.name)
        } else {
            open(tag)
            if voids { close(tag.name) }
        }
    }

    private mutating func open(_ tag: Tag) {
        switch tag.name {
        case "h1", "h2", "h3", "h4", "h5", "h6", "p":
            // A cell stays one line. The first block of a list item keeps the marker.
            guard !inRow else { return }
            openBlock(blankBefore: lists.isEmpty)
        case "li":
            openListItem(tag)
        case "ol":
            let start = Int(tag.attributes["start"] ?? "") ?? 1
            lists.append(List(ordered: true, index: start - 1, tasks: Self.hasClass(tag, "contains-task-list")))
        case "ul":
            lists.append(List(ordered: false, index: 0, tasks: Self.hasClass(tag, "contains-task-list")))
        case "tr":
            openBlock(blankBefore: false)
            inRow = true
            rowCells = 0
        case "div", "section", "article", "blockquote", "header", "footer", "main", "nav", "figure", "figcaption", "dt", "dd":
            guard !inRow else { return }
            openBlock(blankBefore: false)
        case "td", "th":
            if rowCells > 0 { appendRaw(" | ") }
            rowCells += 1
        case "br", "hr":
            if inRow { appendRaw(" ") } else { breakLine() }
        case "pre":
            openBlock(blankBefore: true)
            inPre = true
            preText = ""
        case "code":
            codeDepth = 1
            codeText = ""
        case "input":
            guard isCheckbox(tag) else { return }
            applyCheckbox(checked: isChecked(tag))
        case "a":
            let klass = tag.attributes["class"] ?? ""
            let hide = klass.split(whereSeparator: \.isWhitespace).contains { $0 == "anchor" }
            anchors.append(Anchor(href: tag.attributes["href"] ?? "", hide: hide, emitted: false))
        case "img":
            break
        default:
            break
        }
    }

    private mutating func close(_ name: String) {
        switch name {
        case "a":
            closeAnchor()
        case "pre":
            closePre()
        case "tr":
            flushLine()
            inRow = false
            rowCells = 0
        case "li":
            flushLine()
            pendingPrefix = nil
            looseTaskMarker = nil
            if !taskMarkers.isEmpty { taskMarkers.removeLast() }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            flushLine()
            if lists.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
        case "ol", "ul":
            if !lists.isEmpty { lists.removeLast() }
        case "p", "div", "section", "article", "blockquote",
             "header", "footer", "main", "nav", "figure", "figcaption", "dt", "dd":
            if !inRow { flushLine() }
        default:
            break
        }
    }

    private mutating func openListItem(_ tag: Tag) {
        let previous = lineContainsText ? line : lines.last
        let followsList = previous?.range(
            of: #"^[ \t]*(?:[-*+]|\d{1,3}[.)])[ \t]"#,
            options: .regularExpression
        ) != nil
        openBlock(blankBefore: lists.count <= 1 && !followsList && !inRow)
        looseTaskMarker = nil
        let indent = String(repeating: "  ", count: max(0, lists.count - 1))
        let isTask = (lists.last?.tasks == true) || Self.hasClass(tag, "task-list-item")
        let marker: String
        if isTask {
            let checked = tag.attributes["aria-checked"]?.lowercased() == "true"
            marker = "\(indent)- [\(checked ? "x" : " ")] "
        } else if !lists.isEmpty, lists[lists.count - 1].ordered {
            lists[lists.count - 1].index += 1
            let number = min(lists[lists.count - 1].index, 999)
            marker = "\(indent)\(number). "
        } else {
            marker = "\(indent)- "
        }
        taskMarkers.append(isTask ? marker : nil)
        pendingPrefix = marker
    }

    private mutating func applyCheckbox(checked: Bool) {
        let indent = String(repeating: "  ", count: max(0, lists.count - 1))
        let marker = indent + (checked ? "- [x] " : "- [ ] ")
        if taskMarkers.isEmpty {
            looseTaskMarker = marker
        } else {
            taskMarkers[taskMarkers.count - 1] = marker
        }
        // A checkbox after the row's text has started begins the next row.
        if lineContainsText { flushLine() }
        pendingPrefix = marker
    }

    private var currentTaskMarker: String? {
        if let marker = taskMarkers.last.flatMap({ $0 }) { return marker }
        return looseTaskMarker
    }

    private static func hasClass(_ tag: Tag, _ name: String) -> Bool {
        let klass = tag.attributes["class"] ?? ""
        return klass.split(whereSeparator: \.isWhitespace).contains { $0 == Substring(name) }
    }

    private mutating func handleInsidePre(_ tag: Tag) {
        if tag.name == "br", !tag.closing {
            preText.append("\n")
        } else if tag.name == "pre", tag.closing {
            closePre()
        }
    }

    private mutating func handleInsideCode(_ tag: Tag) {
        if tag.name == "br", !tag.closing {
            codeText.append(" ")
        } else if tag.name == "code", tag.closing {
            codeDepth -= 1
            if codeDepth == 0 { emitCode() }
        } else if tag.name == "code", !tag.closing {
            codeDepth += 1
        }
    }

    private mutating func closePre() {
        inPre = false
        var body = preText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }
        if body.hasSuffix("\n") { body.removeLast() }
        guard DraftText.hasLetters(body) || body.contains(where: \.isNumber) else { return }
        if body.contains("```") {
            body = body.replacingOccurrences(of: "```", with: "``\u{2060}`")
        }
        lines.append("```")
        lines.append(contentsOf: body.components(separatedBy: "\n"))
        lines.append("```")
    }

    private mutating func emitCode() {
        let content = codeText.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        codeText = ""
        guard !content.isEmpty else { return }
        if content.contains("`") {
            let pad = (content.hasPrefix("`") || content.hasSuffix("`")) ? " " : ""
            appendRaw("``\(pad)\(content)\(pad)``")
        } else {
            appendRaw("`\(content)`")
        }
    }

    private mutating func closeAnchor() {
        guard let anchor = anchors.popLast() else { return }
        guard !anchor.hide, !anchor.emitted else { return }
        guard let url = URL(string: anchor.href), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        appendText(anchor.href)
    }

    private func isCheckbox(_ tag: Tag) -> Bool {
        if tag.attributes["type"]?.lowercased() == "checkbox" { return true }
        return tag.attributes["role"]?.lowercased() == "checkbox"
    }

    private func isChecked(_ tag: Tag) -> Bool {
        if tag.attributes["aria-checked"]?.lowercased() == "true" { return true }
        guard let value = tag.attributes["checked"]?.lowercased() else { return false }
        return value != "false"
    }

    private mutating func openBlock(blankBefore: Bool) {
        flushLine()
        // A new block outside the current task item is a new section, not another checkbox row.
        if taskMarkers.last.flatMap({ $0 }) == nil, looseTaskMarker != nil {
            pendingPrefix = nil
            looseTaskMarker = nil
        }
        if blankBefore, let last = lines.last, !last.isEmpty {
            lines.append("")
        }
    }

    private mutating func breakLine() {
        if lineContainsText {
            let marker = currentTaskMarker
            flushLine()
            // `<br>` inside a copied task list is the gap between rows, not a wrap.
            if let marker { pendingPrefix = marker }
        } else if pendingPrefix == nil, lines.last?.isEmpty == false {
            lines.append("")
        }
    }

    /// An empty flush keeps a list marker that the item has not written yet, so a `<p>`
    /// or `<div>` wrapped around the item text does not drop the `- ` / `- [ ]`.
    /// Leading whitespace stays: it is the nested-list indent.
    private mutating func flushLine() {
        var end = line.endIndex
        while end > line.startIndex {
            let previous = line.index(before: end)
            if line[previous] == " " || line[previous] == "\t" {
                end = previous
            } else {
                break
            }
        }
        let trimmed = String(line[..<end])
        line = ""
        guard trimmed.contains(where: { !$0.isWhitespace }) else { return }
        lines.append(trimmed)
        // The next row of this same task item (another `<p>`, `<div>` or `<br>`) keeps the box.
        pendingPrefix = currentTaskMarker
    }

    private var lineContainsText: Bool {
        line.contains { !$0.isWhitespace }
    }

    private var atLineStart: Bool { line.isEmpty }

    private mutating func appendText(_ raw: String) {
        if !skipStack.isEmpty || anchors.last?.hide == true || inPre {
            if inPre, skipStack.isEmpty { preText.append(decode(raw)) }
            return
        }
        if codeDepth > 0 {
            codeText.append(decode(raw))
            return
        }
        var chunk = decode(raw).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !chunk.isEmpty else { return }
        if atLineStart || line.last == " " {
            if chunk.first == " " { chunk.removeFirst() }
        }
        if atLineStart {
            while chunk.first == " " { chunk.removeFirst() }
        }
        guard !chunk.isEmpty else { return }
        appendRaw(chunk)
    }

    private mutating func appendRaw(_ text: String) {
        guard !text.isEmpty, anchors.last?.hide != true else { return }
        if atLineStart, let prefix = pendingPrefix {
            line.append(prefix)
            pendingPrefix = nil
        }
        line.append(text)
        if !anchors.isEmpty {
            anchors[anchors.count - 1].emitted = true
        }
    }

    private func decode(_ source: String) -> String {
        guard source.contains("&") else { return source }
        var result = ""
        result.reserveCapacity(source.count)
        var cursor = source.startIndex
        while cursor < source.endIndex {
            if source[cursor] == "&",
               let end = source[cursor...].firstIndex(of: ";"),
               source.distance(from: cursor, to: end) <= 32,
               let value = decodeEntity(source[source.index(after: cursor)..<end]) {
                result.append(value)
                cursor = source.index(after: end)
                continue
            }
            result.append(source[cursor])
            cursor = source.index(after: cursor)
        }
        return result
    }

    private func decodeEntity(_ body: some StringProtocol) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let scalar: UInt32?
            if digits.first == "x" || digits.first == "X" {
                scalar = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalar = UInt32(digits, radix: 10)
            }
            guard let scalar, let unicode = Unicode.Scalar(scalar) else { return nil }
            if unicode == "\u{00A0}" || unicode == "\u{202F}" { return " " }
            if unicode == "\u{00AD}" { return "" }
            return String(Character(unicode))
        }
        return Self.entities[body.lowercased()]
    }

    private enum TagRead {
        case tag(Tag)
        case ignored
        case notATag
    }

    private struct Tag {
        var name: String
        var closing: Bool
        var selfClosing: Bool
        var attributes: [String: String]
    }

    /// `<` that is not a tag leaves the index where it was.
    private mutating func readTag() -> TagRead {
        let saved = index
        guard index < html.endIndex, html[index] == "<" else { return .notATag }
        let after = html.index(after: index)
        if after < html.endIndex, html[after] == "!" || html[after] == "?" {
            if html[after...].hasPrefix("!--") {
                if let end = html.range(of: "-->", range: after..<html.endIndex) {
                    index = end.upperBound
                } else {
                    index = html.endIndex
                }
            } else if let end = html[after...].firstIndex(of: ">") {
                index = html.index(after: end)
            } else {
                index = html.endIndex
            }
            return .ignored
        }

        index = after
        var closing = false
        if index < html.endIndex, html[index] == "/" {
            closing = true
            index = html.index(after: index)
        }
        let nameStart = index
        while index < html.endIndex {
            let character = html[index]
            if character.isLetter || character.isNumber || character == "-" || character == ":" {
                index = html.index(after: index)
            } else {
                break
            }
        }
        guard nameStart < index else {
            index = saved
            return .notATag
        }
        let name = html[nameStart..<index].lowercased()
        var attributes: [String: String] = [:]
        var selfClosing = false
        while index < html.endIndex {
            while index < html.endIndex, html[index].isWhitespace {
                index = html.index(after: index)
            }
            guard index < html.endIndex else { break }
            if html[index] == "/" {
                selfClosing = true
                index = html.index(after: index)
                continue
            }
            if html[index] == ">" {
                index = html.index(after: index)
                break
            }
            let attributeStart = index
            while index < html.endIndex {
                let character = html[index]
                if character.isWhitespace || character == "=" || character == ">" || character == "/" { break }
                index = html.index(after: index)
            }
            if attributeStart == index {
                index = html.index(after: index)
                continue
            }
            let attribute = html[attributeStart..<index].lowercased()
            while index < html.endIndex, html[index].isWhitespace {
                index = html.index(after: index)
            }
            var value = ""
            if index < html.endIndex, html[index] == "=" {
                index = html.index(after: index)
                while index < html.endIndex, html[index].isWhitespace {
                    index = html.index(after: index)
                }
                if index < html.endIndex, html[index] == "\"" || html[index] == "'" {
                    let quote = html[index]
                    index = html.index(after: index)
                    let valueStart = index
                    while index < html.endIndex, html[index] != quote {
                        index = html.index(after: index)
                    }
                    value = String(html[valueStart..<index])
                    if index < html.endIndex { index = html.index(after: index) }
                } else {
                    let valueStart = index
                    while index < html.endIndex, !html[index].isWhitespace, html[index] != ">" {
                        index = html.index(after: index)
                    }
                    value = String(html[valueStart..<index])
                }
            }
            attributes[attribute] = decode(value)
        }
        return .tag(Tag(name: name, closing: closing, selfClosing: selfClosing, attributes: attributes))
    }
}
