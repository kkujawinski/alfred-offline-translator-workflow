# Development

Everything a user needs is in [README.md](README.md). This covers building, the CLI, and the
release pipeline.

## Requirements

- macOS **26 (Tahoe)** or newer — `TranslationSession(installedSource:target:)` is macOS 26+.
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc`.

## Build

```
./build.sh              build workflow/offtranslate
./build.sh --check      build, then report language availability
./build.sh --icon       regenerate workflow/icon.png
./build.sh --sign       build, then codesign for notarisation
./build.sh --package    build, then produce the .alfredworkflow bundle
```

`SKIP_BUILD=1` skips the compile step, so an already-signed binary survives packaging.

## Repository layout

```
build.sh                        compiles the CLI, checks availability, packages the workflow
src/offtranslate.swift          detection + availability + translation + Alfred JSON
workflow/info.plist             Alfred workflow (Script Filter, Universal Action, hotkey)
workflow/icon.png               workflow icon, 512x512
workflow/images/                screenshots referenced by the in-workflow readme
workflow/offtranslate           built universal binary (git-ignored)
tools/make-icon.swift           redraws icon.png from the system "translate" SF Symbol
fallback/shortcut.md            Shortcuts variant for machines without Xcode CLT
.github/workflows/release.yml   builds, signs, notarises and publishes on every v*.*.* tag
```

---

## How it works

macOS ships Apple's on-device translation models — the ones behind the Translate app and
Safari's "Translate Page". Since macOS 26 they are reachable headlessly from
`Translation.framework`, so a small Swift CLI can call them with no UI and no network.

| Building block | Framework |
|---|---|
| Translation | `Translation` (`TranslationSession`) |
| Language detection | `NaturalLanguage` (`NLLanguageRecognizer`) |
| UI | Alfred Script Filter |

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

**Detection is only as good as its constraint set.** This dictates the CLI design. Constrained
to two languages, even single words resolve cleanly:

```
cat          → en (0.74)      kot         → pl (0.99)
settings     → en (0.97)      ustawienia  → pl (1.00)
Good morning → en (0.99)      Dzień dobry → pl (1.00)
```

Unconstrained across all 16 installed languages, a lone word like `cat` is a coin flip between
Spanish, Italian and Portuguese. So the CLI always narrows the candidate set as far as the
invocation allows: a pair when a pair is known, the installed set only as a last resort.

Two details worth knowing before changing this code:

- `supportedLanguages` returns *maximal* identifiers like `en-Latn-IN`, and not every region
  variant is a valid translation source — `en-Latn-IN → pl` reports `.unsupported` where plain
  `en → pl` works. Detected languages are always rebuilt from the bare code.
- Chinese needs a special case: `Translation` reports `zh` with a script subtag, while
  `NLLanguage` uses `zh-Hans` / `zh-Hant` as whole identifiers.

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

The first word of the text can override the languages inline, which is what the Alfred keyword
uses:

| Prefix | Meaning |
|---|---|
| `>de` | translate into German, detect the source |
| `de>en` | German to English |
| `de>` | from German, into the other half of the pair |

Text that merely starts with `>` is still translated — the override only applies when both
halves look like language codes.

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

**Cross-family pairs route through English.** Apple ships models in families (Polish sits with
`en`/`ru`/`uk`, German with the western set), so `pl → de` has no direct model however many
languages are downloaded. When the direct pair is missing and both sides pair with English, the
CLI translates in two hops and says so in the subtitle: `Polish → English → German`.

**Output.** In Alfred mode the CLI prints Script Filter JSON: the translation as the title, the
resolved direction as the subtitle, and the text in `arg` so <kbd>Enter</kbd> copies it. Missing
models, unsupported pairs, undetectable input and empty queries all come back as a
non-actionable row explaining the fix. In `--plain` mode those same cases go to stderr with exit
code 1.

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
service handshake account for the rest. Reusing one `TranslationSession` in-process drops repeat
calls to ~80 ms, so a resident daemon would save ~150–200 ms per call — not enough to justify
the complexity, so the Script Filter uses a 0.3 s typing delay instead and only fires once you
pause.

---

## Alternatives considered

- **Homebrew** — there is no offline translator in brew. `translate-shell` is a
  Google/Bing/Yandex API client, `translate-toolkit` and `gtranslator` handle PO/XLIFF files
  rather than translating, `mate-translate` is cloud-backed, `plamo-translate` is Japanese-only.
  No `apertium`, `argos-translate`, `bergamot` or `libretranslate` formulae exist.
- **`ollama` + a local LLM** — genuinely offline and better on idioms, but ~5 GB of weights,
  6–10 GB RAM while loaded, a background server, and 1–3 s per call.
- **Shortcuts "Translate Text" + `shortcuts run`** — zero compilation, but ~1–2 s of Shortcuts
  runtime per call. Documented in [`fallback/shortcut.md`](fallback/shortcut.md).
- **`translate://` URL scheme / Translate.app** — opens a window, no way to read the result back.

---

## Releasing

Pushing a `v*.*.*` tag builds, signs, notarises and publishes the workflow as a GitHub Release:

```
git tag v1.1.0
git push origin v1.1.0
```

The job stamps the tag into `info.plist`'s `version` (so Alfred shows the right number), builds,
signs the binary, packages the bundle, submits it to Apple's notary service, checks the bundle
contains `info.plist`, `icon.png` and a universal `offtranslate`, and attaches
`Offline-Translator-v1.1.0.alfredworkflow` with auto-generated notes. `workflow_dispatch` runs
the same job against an existing tag.

It runs on GitHub's hosted **`macos-26`** runner. The Developer ID identity is imported from a
secret into a throwaway keychain for the duration of the job, and deleted afterwards — no
self-hosted machine, no persistent credentials.

### One-time setup

1. **Create the Developer ID Application certificate.** Apple does not allow Developer ID
   certificates to be created through the App Store Connect API at all — only the Account Holder
   can mint one, from the developer portal or Xcode. An API key of any role gets
   `This operation can only be performed by the Account Holder`.
   - Keychain Access → Certificate Assistant → *Request a Certificate From a Certificate
     Authority* → save the CSR to disk.
   - developer.apple.com → Certificates → **+** → **Developer ID Application**, signed in as the
     Account Holder → upload the CSR → download the `.cer`.
   - Install the `.cer`, then export the identity (certificate **and** private key) from Keychain
     Access as a `.p12`, setting a password.

   Developer ID Application is the only type Apple's notary service accepts — "Apple Development"
   and "Apple Distribution" certificates are rejected.
2. **Add five repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `MACOS_CERTIFICATE_P12` | `base64 -i certificate.p12 \| pbcopy` |
   | `MACOS_CERTIFICATE_PASSWORD` | the password set when exporting the `.p12` |
   | `ASC_KEY_ID` | App Store Connect API key ID |
   | `ASC_ISSUER_ID` | issuer ID from Users and Access → Integrations |
   | `ASC_KEY_P8` | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |

   The first two sign; the last three notarise. The API key only submits to the notary service,
   so a non-Account-Holder key is fine there.

### Signing locally

Once a Developer ID certificate is in your keychain:

```
./build.sh && ./build.sh --sign && SKIP_BUILD=1 ./build.sh --package
```

`SKIP_BUILD=1` matters: a plain `--package` recompiles the binary and throws the signature away.
`--sign` defaults to the `Developer ID Application` identity, which `codesign` resolves by
prefix; set `APPLE_SIGNING_IDENTITY` to disambiguate if the keychain holds more than one.

Check the result:

```
codesign -dvv workflow/offtranslate          # Authority, TeamIdentifier, flags=0x10000(runtime)
codesign --verify --strict --verbose=2 …     # silent on success
spctl --assess --type execute --verbose=4 …  # accepted, once notarised
```

### What CI cannot check

Runners have no translation models installed, so the job verifies `--list`, `--help`, the
signature and the bundle contents — never translation output.

The binary is signed with the hardened runtime and notarised, but **not stapled**: `stapler`
only supports bundles, disk images and installer packages, and `offtranslate` is a bare Mach-O
executable. Gatekeeper therefore checks its notarisation online the first time it runs on a new
machine. Because `--sign` passes `--timestamp`, releases stay valid after the certificate
expires; only signing new builds needs a current certificate.
