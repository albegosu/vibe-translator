## What does this change?

<!-- A short description of the change and why it's needed. Link the issue it closes, e.g. "Closes #12". -->

## How was it tested?

<!-- Commands you ran, drafts you translated, apps you tried it in. Screenshots for UI changes. -->

## Checklist

- [ ] `swift build` and `swift test` pass
- [ ] New logic in `VibeTranslatorCore` is covered by tests
- [ ] Safety guarantees are kept: no replacement if the field or text changed, the clipboard is restored, nothing is sent on the user's behalf
- [ ] README / CHANGELOG updated if behavior changed
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
