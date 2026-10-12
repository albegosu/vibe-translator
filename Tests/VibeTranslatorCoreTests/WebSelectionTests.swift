import Testing
@testable import VibeTranslatorCore

struct WebSelectionTests {
    @Test func structuresAWebAreaAndLeavesNativeFieldsAndElectronAlone() {
        #expect(WebSelection.shouldStructure(isElectron: false, isBrowser: true, isInsideWebArea: true, isNativeTextField: false))
        #expect(WebSelection.shouldStructure(isElectron: false, isBrowser: false, isInsideWebArea: true, isNativeTextField: true))
        #expect(!WebSelection.shouldStructure(isElectron: true, isBrowser: false, isInsideWebArea: true, isNativeTextField: false))
        #expect(!WebSelection.shouldStructure(isElectron: false, isBrowser: false, isInsideWebArea: false, isNativeTextField: true))
        #expect(WebSelection.shouldStructure(isElectron: false, isBrowser: true, isInsideWebArea: false, isNativeTextField: false))
        #expect(!WebSelection.shouldStructure(isElectron: false, isBrowser: true, isInsideWebArea: false, isNativeTextField: true))
    }

    @Test func recognizesBrowsersWithoutTreatingTextEditAsOne() {
        #expect(WebSelection.isBrowser(bundleIdentifier: "com.google.Chrome"))
        #expect(WebSelection.isBrowser(bundleIdentifier: "com.google.Chrome.canary"))
        #expect(WebSelection.isBrowser(bundleIdentifier: "com.apple.Safari"))
        #expect(WebSelection.isBrowser(bundleIdentifier: "company.thebrowser.Browser"))
        #expect(WebSelection.isBrowser(bundleIdentifier: "org.mozilla.firefox"))
        #expect(!WebSelection.isBrowser(bundleIdentifier: "com.apple.TextEdit"))
        #expect(!WebSelection.isBrowser(bundleIdentifier: "com.hnc.Discord"))
        #expect(!WebSelection.isBrowser(bundleIdentifier: nil))
    }

    @Test func prefersStructuredHtmlAndKeepsPlainTextWhenTheConversionFlattens() {
        let html = "<p>See <code>delivery_note_files.page_number</code></p>"
        let source = WebSelection.translationSource(plain: "See delivery_note_files.page_number\n", html: html)
        #expect(source == "See `delivery_note_files.page_number`")

        let flat = "<div><span>Description Scope and the rest of the sentence.</span></div>"
        let plain = "Description\n\nScope and the rest of the sentence."
        #expect(WebSelection.translationSource(plain: plain, html: flat) == plain)
        #expect(WebSelection.translationSource(plain: plain, html: nil) == plain)
    }
}

struct StructuredHTMLTests {
    @Test func keepsHeadingsParagraphsLabelsCodeAndCheckboxes() {
        let html = """
        <html><head><title>Ignored outside the fragment</title></head><body><!--StartFragment-->
        <h2>Description</h2>
        <p>A multi-page PDF is extracted. The <code>page</code> field lives on the note, and <code>lineas[]</code> mixes them.</p>
        <h2>Scope</h2>
        <p><strong>In scope:</strong> keep the source page number on every line.</p>
        <p><strong>Out of scope:</strong> changing the model.</p>
        <p><strong>Constraint:</strong> a continuation page stays on that note.</p>
        <h2>Acceptance Criteria</h2>
        <ul class="contains-task-list">
        <li class="task-list-item"><input type="checkbox" disabled=""> After extracting, every line remembers its page</li>
        <li class="task-list-item"><p><input type="checkbox" checked disabled> Continuation lines stay together</p></li>
        </ul>
        <h2>Additional Notes</h2>
        <p>The schema is in <code>server/utils/delivery-note.ts</code> and <code>db/migrations.js</code>.</p>
        <!--EndFragment--><p>Also ignored</p></body></html>
        """
        #expect(StructuredHTML.plainText(from: html) == """
        Description

        A multi-page PDF is extracted. The `page` field lives on the note, and `lineas[]` mixes them.

        Scope

        In scope: keep the source page number on every line.

        Out of scope: changing the model.

        Constraint: a continuation page stays on that note.

        Acceptance Criteria

        - [ ] After extracting, every line remembers its page
        - [x] Continuation lines stay together

        Additional Notes

        The schema is in `server/utils/delivery-note.ts` and `db/migrations.js`.
        """)
    }

    @Test func protectsCodeThroughTheTranslator() async throws {
        let html = """
        <p>Check <code>mergeDeliveryRecordsByNumber</code> please</p>
        <ul>
        <li><input type="checkbox"> Open the preview</li>
        <li><input type="checkbox" checked="checked"> Store the page</li>
        </ul>
        <pre><code>let saludo = "hola"
        keep ``` this</code></pre>
        <p>Done</p>
        """
        let source = try #require(StructuredHTML.plainText(from: html))
        let translated = try await DraftTranslator(engine: UppercaseEngine()).translate(source)
        #expect(translated.text == """
        CHECK `mergeDeliveryRecordsByNumber` PLEASE

        - [ ] OPEN THE PREVIEW
        - [x] STORE THE PAGE

        ```
        let saludo = "hola"
        keep ``\u{2060}` this
        ```

        DONE
        """)
    }

    @Test func rendersOrderedNestedListsEntitiesAndTables() {
        let html = """
        <p>Tom &amp; <b>Jerry</b> &nbsp; say &quot;hi&quot;</p>
        <ol start="2"><li>Second</li><li>Third</li></ol>
        <ul><li>Outer<ul><li>Inner</li></ul></li></ul>
        <table><tr><th>Name</th><th>Page</th></tr><tr><td><p>line</p></td><td>4</td></tr></table>
        <p>Before<br>After<br><br>Gap</p>
        <script>ignored()</script>
        <p>a &lt; b</p>
        """
        #expect(StructuredHTML.plainText(from: html) == """
        Tom & Jerry say "hi"

        2. Second
        3. Third
        - Outer
          - Inner
        Name | Page
        line | 4

        Before
        After

        Gap

        a < b
        """)
    }

    @Test func wrapsCodeThatAlreadyContainsBackticks() {
        #expect(StructuredHTML.plainText(from: "<p>Use <code>a `b` c</code> here</p>") == "Use ``a `b` c`` here")
        #expect(StructuredHTML.plainText(from: "<img alt=\"hidden\"><br>") == nil)
    }

    @Test func repeatsTheCheckboxWhenATaskListIsCopiedAsOneItem() {
        let html = """
        <h2>Acceptance Criteria</h2>
        <ul class="contains-task-list">
        <li class="task-list-item"><input type="checkbox" disabled="" class="task-list-item-checkbox"> A Draft note can move to Incidence, and the comment is stored</li>
        <li class="task-list-item"><input type="checkbox" disabled="" class="task-list-item-checkbox"> An Incidence note can be marked Confirmed by hand</li>
        <li class="task-list-item"><input type="checkbox" checked disabled> A note that is already Confirmed cannot move back</li>
        </ul>
        <ul class="contains-task-list">
        <li class="task-list-item"><input type="checkbox" disabled=""> A Draft note can move to Incidence, and the comment is stored<br>An Incidence note can be marked Confirmed by hand<br>The list and the detail screen distinguish the states</li>
        </ul>
        <p>After the list</p>
        """
        #expect(StructuredHTML.plainText(from: html) == """
        Acceptance Criteria

        - [ ] A Draft note can move to Incidence, and the comment is stored
        - [ ] An Incidence note can be marked Confirmed by hand
        - [x] A note that is already Confirmed cannot move back
        - [ ] A Draft note can move to Incidence, and the comment is stored
        - [ ] An Incidence note can be marked Confirmed by hand
        - [ ] The list and the detail screen distinguish the states

        After the list
        """)
    }

    @Test func restoresCheckboxMarkersThePlainCopyStillHas() {
        let html = """
        <p>A Draft note can move to Incidence, and the comment is stored</p>
        <p>An Incidence note can be marked Confirmed by hand</p>
        <p>The schema is in <code>db/migrations.js</code>.</p>
        """
        let plain = """
        - [ ] A Draft note can move to Incidence, and the comment is stored
        - [x] An Incidence note can be marked Confirmed by hand
        The schema is in db/migrations.js.
        """
        #expect(WebSelection.translationSource(plain: plain, html: html) == """
        - [ ] A Draft note can move to Incidence, and the comment is stored

        - [x] An Incidence note can be marked Confirmed by hand

        The schema is in `db/migrations.js`.
        """)
    }

    @Test func dropsPermalinkAnchorsAndKeepsRealLinks() {
        let html = """
        <h2>Description<a class="anchor" href="#description"><svg><path d="0"></path></svg></a></h2>
        <p>See <a href="https://example.com/doc">the doc</a> and <a href="https://example.com/raw"></a></p>
        """
        #expect(StructuredHTML.plainText(from: html) == """
        Description

        See the doc and https://example.com/raw
        """)
    }
}
