# Alfred Offline Translator

Alfred 5 workflow that translates text **fully offline** using only macOS built-in frameworks.
No API keys, no network, no third-party translation engine.

Any language pair Apple's on-device models support — 23 language codes across 38 locale variants.
English ⇄ Polish is the default pair; everything else is a flag or a second keyword.

Type `tr some text` in Alfred → the translation appears inline → <kbd>Enter</kbd> copies it.
Direction is detected automatically, so one keyword works both ways.

---

## Quick start

```
git clone <this repo> && cd alfred-offline-translator-workflow
./build.sh --check        # build + report which languages are ready
./build.sh --package      # produce "Offline Translator.alfredworkflow"
open "Offline Translator.alfredworkflow"
```

`--check` fails loudly if the default pair's models are not on disk, and tells you where to get
them. For the default EN ⇄ PL setup, **Polish is the only download needed** — English ships
installed.

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
  6–10 GB RAM while loaded, a background server, and 1–3 s per call.
- **Shortcuts "Translate Text" + `shortcuts run`** — zero compilation, but ~1–2 s of Shortcuts
  runtime per call. Documented in [`fallback/shortcut.md`](fallback/shortcut.md) for machines
  without Xcode CLT.
- **`translate://` URL scheme / Translate.app** — opens a window, no way to read the result back.

---

## Requirements

- macOS **26 (Tahoe)** or newer — `TranslationSession(installedSource:target:)` is macOS 26+.
- Alfred 5 with the **Powerpack**.
- Xcode Command Line Tools (`xcode-select --install`) — only to build the binary once.
- The language models you intend to use, downloaded (see below).

---

## Language support

Apple exposes 38 locale variants covering 23 language codes. Most ship pre-installed; the rest
download on demand. As reported by `offtranslate --list` on macOS 26.6.2:

| Status | Languages |
|---|---|
| Installed out of the box (16) | `da` `de` `en` `es` `fr` `it` `ja` `ko` `nb` `nl` `pt` `sv` `tr` `vi` `zh-Hans` `zh-Hant` |
| Supported, needs download (7) | **`pl`** `ar` `hi` `id` `ru` `th` `uk` |

**Downloading a language.** System Settings → General → Language & Region →
**Translation Languages** → add the language. (Or open the Translate app, select the pair, and
accept the prompt.) A headless process cannot show Apple's download prompt, so this step is
manual once per language; `offtranslate` detects a missing model and prints this instruction
rather than failing obscurely.

---

## How it works

```
Alfred Script Filter ──► offtranslate "<query>" ──► JSON for Alfred
                              │
                              ├─ NLLanguageRecognizer, constrained to a candidate set
                              │     └─ picks the source language, target follows from flags
                              │
                              ├─ LanguageAvailability.status(from:to:)
                              │     └─ missing model becomes a readable row, not a crash
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

Unconstrained across all 16 installed languages, a lone word like `cat` is a coin flip between
Spanish, Italian and Portuguese. So the CLI always narrows the candidate set as far as the
invocation allows: a pair when a pair is known, the installed set only as a last resort.

Chinese needs a special case in the mapping — `Translation` reports `zh` with a script subtag,
while `NLLanguage` uses `zh-Hans` / `zh-Hant` as whole identifiers.

---

## CLI

The binary is generic; the Alfred workflow is just one caller.

```
offtranslate [options] [text...]           # text also accepted on stdin

  --pair A,B        two-way pair; detect which side, translate to the other
  --from LANG       explicit source (skips detection)
  --to LANG         explicit target; source detected from the installed set
  --list            print supported languages and their install status
  --plain           print the bare translation instead of Alfred JSON
  --json            force Alfred Script Filter JSON (the default)
  -h, --help        usage
```

`LANG` is a BCP-47 code: `en`, `pl`, `pt-BR`, `zh-Hans`. With no `--pair`/`--from`/`--to`,
the default pair is read from `OFFTRANSLATE_PAIR` (falling back to `en,pl`).

```
$ offtranslate --plain --to de "Good morning, how are you today?"
Guten Morgen, wie geht es dir heute?

$ echo "Bonjour tout le monde" | offtranslate --plain --to en
hello everyone

$ offtranslate --plain ">ja Good morning"
おはようございます

$ offtranslate --plain --from es --to it "Buenos días"
Buongiorno
```

**Output.** In Alfred mode the CLI prints Script Filter JSON: the translation as the title, the
resolved direction as the subtitle, and the text in `arg` so <kbd>Enter</kbd> copies it. Missing
models, unsupported pairs, undetectable input and empty queries all come back as a non-actionable
row explaining the fix. In `--plain` mode those same cases go to stderr with exit code 1.

---

## Usage in Alfred

| Trigger | What it does |
|---|---|
| `tr <text>` | Default pair, direction auto-detected, <kbd>Enter</kbd> copies |
| `tr >de <text>` | Inline target override, no extra keyword needed |
| Universal Action → *Translate offline* | Translate the current selection in any app |
| Hotkey (unassigned by default) | Translate the selection and paste it in place |

The default pair is the `OFFTRANSLATE_PAIR` workflow variable (Alfred → workflow → [x] variables),
so you can switch to `en,de` without rebuilding. For a second permanent pair, duplicate the
Script Filter and give it its own keyword plus a `--pair` argument.

---

## Performance

Measured on an Apple Silicon Mac, macOS 26.6.2:

| Path | Time |
|---|---|
| `--pair` / `--from --to`, short phrase | ~0.5 s |
| same, full sentence | ~1.0 s |
| `--to` only (enumerates installed languages first) | +0.2 s |
| `--list` | 0.17 s |

Roughly 0.35 s of that is the translation itself and is unavoidable; process startup and the
service handshake account for the rest. Reusing one `TranslationSession` in-process drops
repeat calls to ~80 ms, so a resident daemon would save ~150–200 ms per call — not enough to
justify the complexity, so the Script Filter uses a 0.3 s typing delay instead and only fires
once you pause.

---

## Repository layout

```
build.sh                        compiles the CLI, checks availability, packages the workflow
src/offtranslate.swift           detection + availability + translation + Alfred JSON
workflow/info.plist             Alfred workflow (Script Filter, Universal Action, hotkey)
workflow/offtranslate            built universal binary (git-ignored)
fallback/shortcut.md            Shortcuts variant for machines without Xcode CLT
Offline Translator.alfredworkflow   packaged bundle (git-ignored)
```

---

## Limitations

- **macOS 26+ only.** On macOS 15 the same framework exists, but a session can only be created
  from a SwiftUI `.translationTask` modifier, so a headless CLI is not possible.
- **Models are downloaded by hand**, once per language, in System Settings.
- **Single-word input in `--to`-only mode** can be misdetected; use `--pair` or `--from` when the
  input is short and the candidate set is wide.
- **Quality is Apple's.** Good for everyday text, weaker than large cloud models on idioms,
  technical jargon, and long documents.
- **Sub-second, not instant.** See Performance above.

---

## Status

Working. The CLI builds as a universal binary and has been exercised across `--pair`,
`--from/--to`, `--to`-only, stdin, the `>lang` prefix, `--list`, missing-model and empty-input
paths. The Alfred workflow plist validates with `plutil -lint`.

The EN ⇄ PL default pair is blocked only on downloading the Polish model; every other listed
pair works right now.
