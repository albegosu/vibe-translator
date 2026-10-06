# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-10-06

### Added

- Optional list of apps that draft translation is limited to (Settings › General), with app icons, an app picker and − to remove.

### Changed

- Draft translation works in any app by default. The old "only in Discord" switch migrates to the new list: if you had it on, your list starts with Discord.
- The LLM prompt no longer assumes the text comes from Discord.

### Fixed

- Draft translation is blocked in terminals, where pasting several lines would run them as commands.
- Drafts over 4,000 characters aren't translated whole (⌘A in a code editor selects the entire file).

## [0.2.0] - 2026-10-06

### Added

- Improve prompt (experimental, `⌃⌥P`): rewrites the selection or the focused field into a clear prompt (optionally in English) for AI assistants and coding agents, with a preview before replacing. Small requests stay one or two sentences; larger ones get only the sections that add information. Code blocks, file paths, @mentions, URLs, template variables and XML tags are kept intact.
- `VibeTranslator --render-settings <folder>` exports every settings tab as PNG, in light and dark appearance.

### Changed

- Settings is now the standard macOS settings window with General, Traducción and Prompts tabs; each tab scrolls instead of growing past the screen.
- The floating panel takes the keyboard while open: ↩ runs the main action, esc closes and ⌘C copies. Closing it gives the focus back to the app you were in.

### Fixed

- The floating panel no longer runs past the bottom of the screen; near the bottom it grows upwards.
- A Return pressed while the floating panel was open could reach the app underneath and send a chat message.

## [0.1.0] - 2026-10-06

First public release.

### Added

- Menu bar app that translates the focused Discord draft from Spanish to English with a global shortcut, leaving it ready to send.
- Translate selection: translate selected text in any app into a floating panel with Copy and Replace, detecting the direction (English ↔ Spanish).
- Markup protection for mentions, emoji, links, code, formatting, line prefixes, line breaks and indentation, with a fragment-by-fragment fallback.
- Safe replacement that only writes when the field and text are unchanged; Restore original and Copy original.
- Draft access through Accessibility or automated copy and paste, with the clipboard always restored.
- Translation engines: Ollama, Apple Intelligence and Apple Translation, with an automatic fallback chain and output validation.
- Style profile for LLM engines: tone, glossary and extra instructions.
- Configurable shortcuts, settings window, HUD notifications and an app icon.
- Technical validation diagnostics for the focused field.

[Unreleased]: https://github.com/albegosu/vibe-translator/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/albegosu/vibe-translator/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/albegosu/vibe-translator/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/albegosu/vibe-translator/releases/tag/v0.1.0
