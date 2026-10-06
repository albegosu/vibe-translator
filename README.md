<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="VibeTranslator icon">
</p>

<h1 align="center">VibeTranslator</h1>

<p align="center">
  Translate your Discord drafts from Spanish to English with a single keyboard shortcut.<br>
  The translation lands right in the message box, ready for you to review and send.
</p>

<p align="center">
  <a href="https://github.com/albegosu/vibe-translator/actions/workflows/ci.yml"><img src="https://github.com/albegosu/vibe-translator/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black.svg" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.2%2B-orange.svg" alt="Swift 6.2+">
</p>

---

VibeTranslator is a native macOS menu bar app written in Swift. Press a shortcut while writing in Discord and your Spanish draft is replaced with a natural English translation. Mentions, links, emoji, code and formatting stay intact. The app never sends anything: you stay in control of the final message.

It can also translate any text you select, in any app (English → Spanish or Spanish → English), and show the result in a floating panel.

> [!NOTE]
> The app's interface is currently in Spanish.

## Features

- **Translate your draft**: one global shortcut translates the whole Discord draft in place, ready to send.
- **Translate a selection**: select text anywhere (someone's message, a web page, a PDF) and get the translation in a floating panel next to the cursor, with **Copy** and, if the selection is editable, **Replace**. The language is detected automatically.
- **Natural, not literal**: by default an LLM translates with a tone profile ("relaxed technical" out of the box), a glossary of terms to keep, and your own instructions. Idioms and slang are rendered by meaning.
- **Markup is preserved**: mentions (`<@id>`, `@user`, `@everyone`, `#channel`), emoji (Unicode, `:shortcode:`, `<:custom:id>`), links, inline code and code blocks, formatting (`**`, `||`, `~~`…), line prefixes (`>`, `-`, `#`, `-#`), line breaks and indentation.
- **Safe replacement**: the draft is only replaced if the same app, window or channel, field and text are still there. If anything changed while translating, nothing is touched.
- **Undo**: **Restore original** brings your Spanish text back, as long as you haven't edited the translation. **Copy original** works at any time.
- **Clipboard preserved**: whatever you had copied is restored afterwards, and temporary text is marked as transient so clipboard managers ignore it.
- **Pluggable engines with fallback**: Ollama, Apple Intelligence or Apple Translation. If the chosen engine is unavailable, fails or is too slow, Apple Translation takes over automatically.

## Requirements

- **macOS 26 or later** (uses `TranslationSession(installedSource:target:)`). Tested on macOS 27.
- **Xcode 26+ / Swift 6.2+** to build.
- **Accessibility permission**, needed to read the focused field and send ⌘A / ⌘C / ⌘V.
- **Spanish and English language packs** for Apple Translation, downloaded once from the app. They are also the fallback engine.
- Optional: **Apple Intelligence** enabled, or **[Ollama](https://ollama.com)** with a model.

## Installation

There are no prebuilt releases yet; build from source:

```bash
git clone https://github.com/albegosu/vibe-translator.git
cd vibe-translator
scripts/build-app.sh
open build/VibeTranslator.app
```

`scripts/build-app.sh` builds a release binary, assembles `build/VibeTranslator.app` and signs it ad hoc.

### Keeping the Accessibility permission across rebuilds

macOS ties the Accessibility permission to the app's code signature. With an ad hoc signature, **every rebuild looks like a new app** and you have to remove and re-add VibeTranslator in *System Settings › Privacy & Security › Accessibility*.

To avoid that, create a code-signing certificate once: in *Keychain Access › Certificate Assistant › Create a Certificate…*, name it `VibeTranslator Dev` and choose type *Code Signing*. Then build with:

```bash
CODESIGN_IDENTITY="VibeTranslator Dev" scripts/build-app.sh
```

## First run

1. Open the app. A speech-bubble icon appears in the menu bar.
2. Grant the Accessibility permission when macOS asks (or from the menu).
3. Open **Idiomas español → inglés…** in the menu and download the language packs.
4. Pick a translation engine in **Ajustes…** (Settings). See [Translation engines](#translation-engines).
5. In Discord, write a draft, keep the cursor in the message box and press `⌃⌥T`.

## Usage

| Shortcut (default) | Action |
| --- | --- |
| `⌃⌥T` | Translate the current draft (Spanish → English) in place |
| `⌃⌥Z` | Restore the original draft |
| `⌃⌥Y` | Translate the selected text in a floating panel (direction detected automatically) |

All shortcuts can be changed or removed in Settings. The draft shortcut only acts in Discord by default ("Traducir el borrador solo en Discord"); translating a selection works in any app.

## Translation engines

| Engine | What it offers | Privacy |
| --- | --- | --- |
| **Apple Intelligence** (default) | On-device LLM; follows the tone, glossary and your instructions | Everything stays on your Mac |
| **Ollama** | Any model you choose, with the same style profile. `gemma4:12b` works well locally; `gemma4:31b-cloud` if you'd rather not load your Mac | Local, except `…cloud` models, which the app labels as cloud |
| **Apple Translation** | Classic machine translation: fast and reliable, but no tone control | Everything stays on your Mac |

LLM engines receive the whole draft in a single request (`{"lines": [...]}`), so every line has the context of the others. Responses are validated:

- one line per input line;
- no empty lines;
- no disproportionately long lines, which usually mean the model answered the message instead of translating it.

If a check fails, or the engine takes longer than 20 s, the draft is translated with Apple Translation and the notification says so.

The style profile (tone, glossary, extra instructions) lives in **Settings › Estilo** and applies on the next translation, without restarting.

## How it works

### Reading and replacing the draft

| Method | Read | Write |
| --- | --- | --- |
| Accessibility | `AXValue` of the focused element | Select all, replace `AXSelectedText` (or `AXValue`) and read back to verify |
| Clipboard | ⌘A ⌘C, then restore the clipboard | ⌘A ⌘C (check nothing changed), ⌘V, then restore the clipboard |

**Automatic** (the default) uses the clipboard in Electron apps such as Discord and Accessibility in native text fields, falling back to the clipboard. Discord's editor (Slate) keeps its own document model, so:

- writing through Accessibility can change what you see without changing what gets sent;
- the editor's own copy and paste handlers keep mentions and custom emoji in their canonical form (`<@id>`, `<:name:id>`).

⌘A / ⌘C / ⌘V are resolved against the active keyboard layout, so they also work with AZERTY, Dvorak and others.

### Protecting markup

`DraftTranslator` (in `VibeTranslatorCore`) works line by line:

1. Fenced code blocks are left untouched.
2. Indentation and line prefixes are kept aside.
3. Every protected span becomes a `{n}` placeholder and the whole line is translated, so the engine keeps the sentence context.
4. Each placeholder must come back **exactly once**. If the engine dropped or duplicated one, that line is translated fragment by fragment instead, so markup is never lost.
5. The first letter of each line is matched to the original's case, whatever the engine returned.

## Privacy

- VibeTranslator has no server, no analytics and no telemetry.
- Your settings live in macOS preferences; diagnostic reports are saved locally in `~/Library/Logs/VibeTranslator/`.
- Text only leaves your Mac if you choose an Ollama cloud model. In that case it goes to Ollama through the Ollama app on your Mac.
- Your clipboard is saved and restored around every automated copy and paste.

## Technical validation

The menu's **Validación técnica** entry runs diagnostics on the focused field:

- **Diagnose focused field**: after 3 s, reports the macOS and app versions, whether the app is Electron, the result of `AXManualAccessibility`, the element's role, attributes and writable properties, and compares `AXValue` with what ⌘A ⌘C returns.
- **Diagnose and test writing** (with an **empty** draft): also checks whether writing through Accessibility reaches the editor's model (not only the DOM) and whether a multi-line paste arrives intact. The field is cleared afterwards; nothing is ever sent.

The report opens in a window and is saved to `~/Library/Logs/VibeTranslator/`.

## Project structure

```
Sources/VibeTranslatorCore/       Pure, tested logic
  DraftMarkup.swift               Discord markup recognition
  DraftTranslator.swift           Line-by-line pipeline, placeholders, engine fallback chain
  TranslationStyle.swift          Tone profile and LLM prompt / response format
  LanguageDirection.swift         Language detection for "translate selection"
Sources/VibeTranslator/           Menu bar app
  AppModel.swift                  Orchestrates translate / restore / selection / diagnostics
  Draft/                          Safe reading and replacing (Accessibility and clipboard)
  Translation/                    Ollama, Apple Intelligence and Apple Translation engines
  System/                         Accessibility, global shortcuts (Carbon), keyboard, clipboard
  Settings/ UI/ Diagnostics/      Settings, HUD, floating panel, validation report
Tests/VibeTranslatorCoreTests/    Unit tests (Swift Testing)
scripts/                          App bundle build and icon generation
```

## Known limitations

- Draft translation is Spanish → English only; selection translation detects the direction.
- Tone only applies to LLM engines; Apple Translation doesn't take instructions.
- Replacing a selection has no "Restore original"; use ⌘Z in the app itself.
- Markdown links (`[text](url)`) are kept whole, without translating the text.
- A translation longer than Discord's character limit may make Discord offer to send it as a file.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 albegosu
