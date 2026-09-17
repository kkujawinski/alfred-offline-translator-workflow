# Alfred Offline Translator (EN ⇄ PL)

Alfred 5 workflow that translates between English and Polish **fully offline**, using only
macOS built-in frameworks. No API keys, no network, no third-party translation engine.

Type `tr some text` in Alfred → the translation appears inline → <kbd>Enter</kbd> copies it.
Direction is detected automatically, so the same keyword works both ways.

---

## Why this approach

macOS ships Apple's on-device translation models (the ones behind the Translate app and
Safari's "Translate Page"). Since macOS 26 they are reachable headlessly from
`Translation.framework`, which means a tiny Swift CLI can call them with no UI and no network.

| Building block | Framework | Ships with macOS |
|---|---|---|
| Translation | `Translation` (`TranslationSession`) | yes |
| Language detection (EN vs PL) | `NaturalLanguage` (`NLLanguageRecognizer`) | yes |
| Compiler | `swiftc` (Xcode Command Line Tools) | yes, one-time install |
| UI | Alfred Script Filter | Alfred 5 (Powerpack) |

Everything runs on the local neural translation models. Airplane mode changes nothing.

### Alternatives considered

- **Shortcuts "Translate Text" + `shortcuts run`** — zero compilation, but every call spins up
  the Shortcuts runtime (~1–2 s), which is too slow for a live Script Filter. Kept as a documented
  fallback for machines without Xcode CLT.
- **`translate://` URL scheme / Translate.app** — opens a window, no way to read the result back.
- **Third-party engines** (Argos Translate, LibreTranslate, ct2/Marian models) — offline, but not
  built-in: a Python runtime plus a few hundred MB of models.

---

## Requirements

- macOS **26 (Tahoe)** or newer — `TranslationSession(installedSource:target:)` is macOS 26+.
- Alfred 5 with the **Powerpack**.
- Xcode Command Line Tools (`xcode-select --install`) — only to build the binary once.
- English and Polish translation models downloaded on the machine (see setup).

---

## One-time setup

1. **Download the offline models.**
   System Settings → General → Language & Region → **Translation Languages** → download
   **English** and **Polish**. (Or open the Translate app, pick EN → PL, and accept the
   download prompt.)
   The models are a few hundred MB each and stay on disk.
2. **Build the helper binary.**
   ```
   ./build.sh
   ```
   Produces `workflow/octranslate` (a single self-contained arm64 executable).
3. **Install the workflow.**
   Double-click the generated `Alfred Offline Translator.alfredworkflow`, or open the
   `workflow/` folder from Alfred's workflow editor.

`./build.sh --check` verifies that both language pairs are actually installed and prints what
is missing.

---

## How it works

```
Alfred Script Filter ──► octranslate "<query>" ──► JSON for Alfred
                              │
                              ├─ NLLanguageRecognizer (constrained to en + pl)
                              │     └─ decides direction: en→pl or pl→en
                              │
                              └─ TranslationSession(installedSource:target:)
                                    └─ on-device neural model → translated text
```

**Direction detection.** `NLLanguageRecognizer` is constrained to English and Polish only, so it
never proposes a third language and stays reliable even on single words:

```
cat        → en (0.74)        kot         → pl (0.99)
settings   → en (0.97)        ustawienia  → pl (1.00)
Good morning → en (0.99)      Dzień dobry → pl (1.00)
```

Ambiguous input can be forced with a prefix: `tr >pl text` translates to Polish,
`tr >en tekst` translates to English.

**Output.** The CLI prints Alfred Script Filter JSON: one row with the translation as the title,
the detected direction as the subtitle, and the text in `arg` so <kbd>Enter</kbd> copies it.
`--plain` prints just the translated string, for piping.

---

## Usage

| Trigger | What it does |
|---|---|
| `tr <text>` | Translate as you type, <kbd>Enter</kbd> copies the result |
| Universal Action → *Translate EN ⇄ PL* | Translate the current selection in any app |
| Hotkey (unassigned by default) | Translate the selected text and paste it in place |

CLI, independently of Alfred:

```
$ octranslate --plain "Good morning, how are you today?"
Dzień dobry, jak się dzisiaj masz?

$ echo "Jak się masz?" | octranslate --plain
How are you?
```

---

## Repository layout

```
build.sh                  compiles the Swift CLI, packages the .alfredworkflow
src/octranslate.swift     the whole translator: detection + translation + Alfred JSON
workflow/info.plist       Alfred workflow definition (keyword, universal action, hotkey)
workflow/octranslate      built binary (git-ignored)
fallback/shortcut.md      Shortcuts-based variant for machines without Xcode CLT
```

---

## Limitations

- **macOS 26+ only.** On macOS 15 the same framework exists but a session can only be created
  from a SwiftUI `.translationTask` modifier, so a headless CLI is not possible.
- **Models must be downloaded by hand.** A command-line process cannot show Apple's download
  prompt; `octranslate` detects the missing model and tells you where to get it.
- **Quality is Apple's.** Good for everyday text, weaker than large cloud models on idioms,
  technical jargon, and long documents.
- **First call after boot** takes ~0.5 s while the model loads; subsequent calls are fast.

---

## Status

README first. `src/octranslate.swift`, `build.sh` and the Alfred workflow are the next step.
The framework path is verified working on macOS 26.6.2: `Translation` and `NaturalLanguage`
both respond correctly from a plain `swiftc`-built CLI.
