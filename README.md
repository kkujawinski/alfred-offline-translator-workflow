# Alfred Offline Translator

Alfred 5 workflow that translates text **fully offline** using only macOS built-in frameworks.
No API keys, no network, no third-party translation engine.

Any language pair Apple's on-device models support — 22 languages, 38 locale variants.
English ⇄ Polish is the default pair; everything else is a flag or a second keyword.

Type `tr some text` in Alfred → the translation appears inline → <kbd>Enter</kbd> copies it.
Direction is detected automatically, so one keyword works both ways.

---

## Why this approach

macOS ships Apple's on-device translation models — the ones behind the Translate app and
Safari's "Translate Page". Since macOS 26 they are reachable headlessly from
`Translation.framework`, so a small Swift CLI can call them with no UI and no network.

| Building block | Framework | Ships with macOS |
|---|---|---|
| Translation | `Translation` (`TranslationSession`) | yes |
| Language detection | `NaturalLanguage` (`NLLanguageRecognizer`) | yes |
| Compiler | `swiftc` (Xcode Command Line Tools) | yes, one-time install |
| UI | Alfred Script Filter | Alfred 5 (Powerpack) |

Airplane mode changes nothing.

### Alternatives considered

- **Homebrew** — there is no offline translator in brew. `translate-shell` is a Google/Bing/Yandex
  API client, `translate-toolkit` and `gtranslator` handle PO/XLIFF files rather than translating,
  `mate-translate` is cloud-backed, `plamo-translate` is Japanese-only. No `apertium`,
  `argos-translate`, `bergamot` or `libretranslate` formulae exist.
- **`ollama` + a local LLM** — genuinely offline and better on idioms, but ~5 GB of weights,
  6–10 GB RAM while loaded, a background server, and 1–3 s per call. Too slow for a Script Filter
  that fires on every keystroke.
- **Shortcuts "Translate Text" + `shortcuts run`** — zero compilation, but ~1–2 s of Shortcuts
  runtime per call. Kept as a documented fallback for machines without Xcode CLT.
- **`translate://` URL scheme / Translate.app** — opens a window, no way to read the result back.

---

## Requirements

- macOS **26 (Tahoe)** or newer — `TranslationSession(installedSource:target:)` is macOS 26+.
- Alfred 5 with the **Powerpack**.
- Xcode Command Line Tools (`xcode-select --install`) — only to build the binary once.
- The language models you intend to use, downloaded (see below).

---

## Language support

Apple exposes 38 locale variants covering 22 languages. Most ship pre-installed; the rest
download on demand. As probed on macOS 26.6.2:

| Status | Languages |
|---|---|
| Installed out of the box | `da` `de` `en` `es` `fr` `it` `ja` `ko` `nb` `nl` `pt` `sv` `tr` `vi` `zh` |
| Supported, needs download | `pl` `ar` `hi` `id` `ru` `th` `uk` |

`octranslate --list` prints the live status on your machine.

**Downloading a language.** System Settings → General → Language & Region →
**Translation Languages** → add the language. (Or open the Translate app, select the pair, and
accept the prompt.) A headless process cannot show Apple's download prompt, so this step is
manual once per language; `octranslate` detects a missing model and prints this instruction.

For the default EN ⇄ PL setup, **Polish is the only download needed** — English is already there.

---

## How it works

```
Alfred Script Filter ──► octranslate "<query>" ──► JSON for Alfred
                              │
                              ├─ NLLanguageRecognizer, constrained to a candidate set
                              │     └─ picks the source language, target follows from flags
                              │
                              └─ TranslationSession(installedSource:target:)
                                    └─ on-device neural model → translated text
```

**Detection is only as good as its constraint set.** This is the one thing that dictates the CLI
design. Constrained to two languages, even single words resolve cleanly:

```
cat        → en (0.74)        kot         → pl (0.99)
settings   → en (0.97)        ustawienia  → pl (1.00)
Good morning → en (0.99)      Dzień dobry → pl (1.00)
```

Unconstrained across all 15 installed languages, a lone word like `cat` is a coin flip between
Spanish, Italian and Portuguese. So the CLI always narrows the candidate set as far as the
invocation allows: a pair when a pair is known, the installed set only as a last resort.

Chinese needs a special case in the mapping — `Translation` reports `zh`, while `NLLanguage`
distinguishes `zh-Hans` and `zh-Hant`.

---

## CLI

The binary is generic; the Alfred workflow is just one caller.

```
octranslate [options] [text...]           # text also accepted on stdin

  --pair A,B        two-way pair; detect which side, translate to the other
  --from LANG       explicit source (skips detection)
  --to LANG         explicit target; source detected from the installed set
  --list            print supported languages and their install status
  --plain           print the bare translation instead of Alfred JSON
  --json            force Alfred Script Filter JSON (default when run from Alfred)
```

`LANG` is a BCP-47 code: `en`, `pl`, `pt-BR`, `zh-Hans`. With no `--pair`/`--from`/`--to`,
the default pair is read from `OCTRANSLATE_PAIR` (falling back to `en,pl`).

```
$ octranslate --plain "Good morning, how are you today?"
Dzień dobry, jak się dzisiaj masz?

$ echo "Jak się masz?" | octranslate --plain
How are you?

$ octranslate --plain --to de "Good morning"
Guten Morgen

$ octranslate --plain --from pl --to ja "Cześć"
こんにちは
```

**Output.** In Alfred mode the CLI prints Script Filter JSON: the translation as the title, the
resolved direction as the subtitle, and the text in `arg` so <kbd>Enter</kbd> copies it. Missing
models, unsupported pairs and empty input come back as a non-actionable row explaining the fix,
never as a crash.

---

## Usage in Alfred

| Trigger | What it does |
|---|---|
| `tr <text>` | Default pair, translate as you type, <kbd>Enter</kbd> copies |
| `trde <text>`, `trja <text>` … | Same binary with a different `--to`; add one keyword per pair you use |
| `tr >de <text>` | Inline target override, no extra keyword needed |
| Universal Action → *Translate* | Translate the current selection in any app |
| Hotkey (unassigned by default) | Translate the selected text and paste it in place |

---

## Repository layout

```
build.sh                  compiles the Swift CLI, packages the .alfredworkflow
src/octranslate.swift     detection + translation + Alfred JSON
workflow/info.plist       Alfred workflow definition (keywords, universal action, hotkey)
workflow/octranslate      built binary (git-ignored)
fallback/shortcut.md      Shortcuts-based variant for machines without Xcode CLT
```

`./build.sh --check` builds, then verifies that the default pair's models are installed and
prints what is missing.

---

## Limitations

- **macOS 26+ only.** On macOS 15 the same framework exists, but a session can only be created
  from a SwiftUI `.translationTask` modifier, so a headless CLI is not possible.
- **Models are downloaded by hand**, once per language, in System Settings.
- **Single-word input in `--to`-only mode** can be misdetected; use `--pair` or `--from` when the
  input is short and the language set is wide.
- **Quality is Apple's.** Good for everyday text, weaker than large cloud models on idioms,
  technical jargon, and long documents.
- **First call after boot** takes ~0.5 s while the model loads; subsequent calls are fast.

---

## Status

README first. `src/octranslate.swift`, `build.sh` and the Alfred workflow are the next step.
The framework path is verified on macOS 26.6.2: `Translation` enumerates 38 locales and reports
per-language install status, and `NLLanguageRecognizer` resolves EN/PL correctly from a plain
`swiftc`-built CLI — no Xcode project, no entitlements, no network.
