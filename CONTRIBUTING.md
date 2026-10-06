# Contributing to VibeTranslator

Thanks for taking the time to contribute! Bug reports, ideas, documentation fixes and code are all welcome.

By participating you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug**: open an [issue](https://github.com/albegosu/vibe-translator/issues/new/choose) using the bug report template. Attaching the output of *Validación técnica › Diagnosticar campo activo* helps a lot. Review it first: it can include a preview of the text in the focused field.
- **Suggest a feature**: open an issue with the feature request template and describe the problem before the solution.
- **Send a pull request**: for anything bigger than a small fix, open an issue first so we can agree on the approach.
- **Security issues**: please don't open a public issue; follow [SECURITY.md](SECURITY.md).

## Development setup

Requirements: macOS 26 or later and Xcode 26+ (Swift 6.2+).

```bash
git clone https://github.com/albegosu/vibe-translator.git
cd vibe-translator
swift build
swift test
```

To run the app:

```bash
scripts/build-app.sh
open build/VibeTranslator.app
```

macOS ties the Accessibility permission to the code signature, so with the default ad hoc signature you'll need to grant it again after every rebuild. The README explains how to [sign with a stable local certificate](README.md#keeping-the-accessibility-permission-across-rebuilds) to avoid that.

Handy scripts:

- `swift scripts/make-icon.swift`: regenerates the app icon and the README logo.
- `swift scripts/inspect-pasteboard.swift`: prints every format on the clipboard (read-only), including Chromium's web custom data. Copy something in an editor first; it shows how that editor serializes mentions, emoji and other rich content.
- `scripts/make-demo-gif.sh <recording.mov>`: turns a screen recording into `docs/assets/demo.gif`.

## Project layout

- `Sources/VibeTranslatorCore`: pure logic (markup protection, translation pipeline, engine fallback, prompts, language detection). No AppKit. **Everything here should be covered by tests.**
- `Sources/VibeTranslator`: the menu bar app (Accessibility, clipboard, global shortcuts, engines, UI).
- `Tests/VibeTranslatorCoreTests`: unit tests written with Swift Testing.

See the [README](README.md#how-it-works) for how drafts are read, protected, translated and written back.

## Guidelines

### Code

- Follow the style of the surrounding code: Swift 6 strict concurrency, `@MainActor` for anything touching AppKit or Accessibility, small focused types.
- Code, identifiers and comments are in **English**. User-facing strings are currently in **Spanish**.
- Keep logic that can be tested in `VibeTranslatorCore`, and add or update tests for it.
- Never weaken the safety guarantees: the draft must only be replaced if the field and text are unchanged, the user's clipboard must always be restored, and nothing may ever be sent on the user's behalf.
- Don't add dependencies without discussing it in an issue first.

### Adding a translation engine

Implement the `TranslationEngine` protocol: one output per input, in order. Inputs contain `{n}` placeholders that must come back untouched. LLM-based engines should use `LLMPrompt` for instructions and response parsing. Then add the engine to `EngineKind` and `AppModel.makeTranslator`. Apple Translation stays as the last engine in the chain, as the fallback.

### Commits

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat: …`, `fix: …`, `docs: …`, `refactor: …`, `test: …`, `chore: …`.
- Keep each commit focused on one change.

### Pull requests

1. Fork the repository and create a branch from `main` (for example `feat/selection-history` or `fix/mention-pills`).
2. Make your change, with tests where it makes sense.
3. Make sure `swift build` and `swift test` pass. CI runs both on every pull request.
4. Fill in the pull request template, including how you tested it. Screenshots are welcome for UI changes.
5. Keep the pull request small and focused; it makes review much faster.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
