# Security Policy

VibeTranslator runs with the macOS Accessibility permission, reads the focused text field and uses the clipboard, so we take security reports seriously.

## Supported versions

Only the latest code on the `main` branch is supported. There are no prebuilt releases yet.

## Reporting a vulnerability

**Please do not report security issues in public issues, discussions or pull requests.**

Use GitHub's private vulnerability reporting: open the repository's [**Security** tab](https://github.com/albegosu/vibe-translator/security) and click **Report a vulnerability**. Please include:

- a description of the issue and its impact;
- steps to reproduce, or a proof of concept;
- your macOS version, and the app involved (for example the Discord version).

You can expect an acknowledgement within a week. Once the issue is confirmed, we'll work on a fix and agree with you on a disclosure date. Credit is given to reporters who want it.

## Scope

Examples of what we consider in scope:

- text being read from, or written to, an app or field other than the one the user is working in;
- clipboard contents being leaked, kept or not restored;
- the app sending a message, or typing anything beyond the translation, without the user's action;
- text reaching a network destination the user didn't choose (only the configured Ollama server is ever contacted);
- prompt-injection paths that make an LLM engine output something other than a translation that then gets written into the user's draft.

Out of scope: vulnerabilities in third-party software (macOS, Discord, Ollama, the models themselves) unless VibeTranslator makes them exploitable.
