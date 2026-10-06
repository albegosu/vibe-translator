# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
