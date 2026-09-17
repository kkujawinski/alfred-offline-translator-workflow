# Fallback: Shortcuts instead of the Swift binary

Use this only if you cannot install the Xcode Command Line Tools. It reaches the same
on-device models through the Shortcuts app, so it is equally offline — just slower
(~1–2 s per call versus ~0.5 s) because every invocation boots the Shortcuts runtime.

## Build the shortcut

1. Open **Shortcuts** → File → New Shortcut, name it `Translate Offline`.
2. Shortcut Details (ⓘ) → tick **Use as Quick Action** and **Receive text input**.
3. Add these actions in order:

   | # | Action | Configuration |
   |---|---|---|
   | 1 | **Detect Language** | Input: *Shortcut Input* |
   | 2 | **If** | *Detected Language* **is** `pl` |
   | 3 | └ **Translate Text** | Text: *Shortcut Input*, From: Polish, To: English |
   | 4 | **Otherwise** | |
   | 5 | └ **Translate Text** | Text: *Shortcut Input*, From: English, To: Polish |
   | 6 | **End If** | |
   | 7 | **Stop and Output** | Output: *Translated Text* |

4. Run it once from the Shortcuts app and accept the language-download prompt.
   This is the step the Swift CLI cannot do, so doing it here also unblocks the CLI.

## Call it from Alfred

Replace the Script Filter's script with:

```zsh
result=$(printf '%s' "$1" | shortcuts run "Translate Offline" 2>/dev/null)
[ -z "$result" ] && result="(no translation)"
printf '{"items":[{"title":%s,"subtitle":"Shortcuts (offline)","arg":%s,"valid":true}]}' \
  "$(printf '%s' "$result" | plutil -convert json -o - -)" \
  "$(printf '%s' "$result" | plutil -convert json -o - -)"
```

Set the Script Filter's queue delay to at least 0.5 s — Shortcuts cannot keep up with
per-keystroke invocation.

## Limits versus the Swift CLI

- One shortcut per language pair; the `--to`/`--pair` flags have no equivalent.
- Language codes in **Detect Language** are Apple's, and the *Translate Text* action's
  language pickers are fixed at edit time — there is no way to set them from a variable.
- No availability check, so a missing model surfaces as empty output rather than a message.
