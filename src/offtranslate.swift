// offtranslate — offline translation via Apple's on-device models.
//
// Uses Translation.framework for the translation itself and NLLanguageRecognizer
// for source-language detection. No network, no third-party engine.

import Foundation
import NaturalLanguage
import Translation

// MARK: - Language plumbing

/// Translation reports `zh`; NLLanguage distinguishes `zh-Hans` and `zh-Hant`.
func nlLanguage(for language: Locale.Language) -> NLLanguage? {
    guard let code = language.languageCode?.identifier else { return nil }
    if code == "zh" {
        return NLLanguage(rawValue: language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans")
    }
    return NLLanguage(rawValue: code)
}

func code(of language: Locale.Language) -> String {
    guard let code = language.languageCode?.identifier else { return language.maximalIdentifier }
    if code == "zh" { return language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans" }
    return code
}

func displayName(of language: Locale.Language) -> String {
    let id = code(of: language)
    return Locale.current.localizedString(forIdentifier: id)
        ?? Locale.current.localizedString(forLanguageCode: id)
        ?? id
}

/// One entry per distinct language code, so `en-GB` and `en-US` do not both
/// end up in a detection constraint set.
///
/// Each entry is rebuilt from the bare code. `supportedLanguages` hands back
/// maximal identifiers like `en-Latn-IN`, and not every region variant is a
/// supported translation source — `en-Latn-IN` to `pl` reports `.unsupported`
/// where plain `en` to `pl` works. Detection only ever identifies a language,
/// never a region, so the region has to be dropped before the pair is used.
func deduplicated(_ languages: [Locale.Language]) -> [Locale.Language] {
    var seen = Set<String>()
    return languages.compactMap { language in
        let identifier = code(of: language)
        return seen.insert(identifier).inserted ? Locale.Language(identifier: identifier) : nil
    }
}

func detect(_ text: String, among candidates: [Locale.Language]) -> Locale.Language? {
    guard candidates.count > 1 else { return candidates.first }
    let recognizer = NLLanguageRecognizer()
    recognizer.languageConstraints = candidates.compactMap(nlLanguage(for:))
    recognizer.processString(text)
    guard let dominant = recognizer.dominantLanguage else { return nil }
    return candidates.first { nlLanguage(for: $0) == dominant }
}

// MARK: - Output

enum OutputMode { case alfred, plain }

struct Row {
    var title: String
    var subtitle: String
    var arg: String?
}

func emit(_ rows: [Row], mode: OutputMode, failed: Bool = false) -> Never {
    switch mode {
    case .plain:
        if failed {
            FileHandle.standardError.write(Data((rows[0].title + ": " + rows[0].subtitle + "\n").utf8))
            exit(1)
        }
        print(rows[0].arg ?? rows[0].title)
    case .alfred:
        let items: [[String: Any]] = rows.map { row in
            var item: [String: Any] = [
                "title": row.title,
                "subtitle": row.subtitle,
                "valid": row.arg != nil,
            ]
            if let arg = row.arg {
                item["arg"] = arg
                item["text"] = ["copy": arg, "largetype": arg]
            }
            return item
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["items": items])) ?? Data("{\"items\":[]}".utf8)
        FileHandle.standardOutput.write(data)
    }
    exit(0)
}

// MARK: - Arguments

struct Options {
    var from: Locale.Language?
    var to: Locale.Language?
    var pair: [Locale.Language]?
    var list = false
    var mode: OutputMode = .alfred
    var text = ""
}

let usage = """
offtranslate — offline translation using macOS on-device models

USAGE
  offtranslate [options] [text...]        text is also accepted on stdin

OPTIONS
  --pair A,B      two-way pair: detect which side the text is, translate to the other
  --from LANG     explicit source language (skips detection)
  --to LANG       explicit target language; source detected from installed languages
  --list          print supported languages and their install status
  --plain         print the bare translation instead of Alfred Script Filter JSON
  --json          force Alfred Script Filter JSON (the default)
  -h, --help      this text

LANG is a BCP-47 code: en, pl, pt-BR, zh-Hans.
With no --pair/--from/--to, the pair comes from OFFTRANSLATE_PAIR (default "en,pl").

The first word can override the languages inline:
  ">de hello"          translate into German, detecting the source
  "de>en Schmetterling"  German to English
  "de> Schmetterling"    from German, into the other half of the pair

When no direct model exists for a pair, the translation routes through English.
"""

func parse(_ argv: [String]) -> Options {
    var options = Options()
    var words: [String] = []
    var index = 0
    while index < argv.count {
        let argument = argv[index]
        func value() -> String {
            index += 1
            return index < argv.count ? argv[index] : ""
        }
        switch argument {
        case "--from": options.from = Locale.Language(identifier: value())
        case "--to": options.to = Locale.Language(identifier: value())
        case "--pair":
            options.pair = value().split(separator: ",")
                .map { Locale.Language(identifier: $0.trimmingCharacters(in: .whitespaces)) }
        case "--list": options.list = true
        case "--plain": options.mode = .plain
        case "--json": options.mode = .alfred
        case "-h", "--help": print(usage); exit(0)
        default: words.append(argument)
        }
        index += 1
    }
    options.text = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

    // Inline language override on the first word:
    //   ">de text"      target German, source detected
    //   "de>en text"    German to English
    //   "de> text"      from German, target is the other half of the pair
    let token = String(options.text.prefix { !$0.isWhitespace })
    if token.contains(">") {
        let halves = token.split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
        let left = halves.count > 0 ? String(halves[0]) : ""
        let right = halves.count > 1 ? String(halves[1]) : ""

        // Only treat it as an override when both halves look like language
        // codes, so ordinary text beginning with ">" is still translated.
        func isCode(_ string: String) -> Bool {
            !string.isEmpty && string.count <= 10 && string.allSatisfy { $0.isLetter || $0 == "-" }
        }
        let leftOK = left.isEmpty || isCode(left)
        let rightOK = right.isEmpty || isCode(right)

        if leftOK, rightOK, !(left.isEmpty && right.isEmpty) {
            if isCode(left) { options.from = Locale.Language(identifier: left) }
            if isCode(right) {
                options.to = Locale.Language(identifier: right)
                // An explicit target replaces the configured pair; a bare
                // "de>" keeps it, because the pair supplies the target.
                options.pair = nil
            }
            options.text = options.text.dropFirst(token.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return options
}

func defaultPair() -> [Locale.Language] {
    let raw = ProcessInfo.processInfo.environment["OFFTRANSLATE_PAIR"] ?? "en,pl"
    let languages = raw.split(separator: ",")
        .map { Locale.Language(identifier: $0.trimmingCharacters(in: .whitespaces)) }
    return languages.count == 2 ? languages : [Locale.Language(identifier: "en"), Locale.Language(identifier: "pl")]
}

// MARK: - Main

@main
struct OCTranslate {
    static let availability = LanguageAvailability()

    static func installed(_ all: [Locale.Language]) async -> [Locale.Language] {
        var result: [Locale.Language] = []
        for language in all where await availability.status(from: language, to: nil) == .installed {
            result.append(language)
        }
        return result
    }

    static func runList() async -> Never {
        let all = deduplicated(await availability.supportedLanguages)
            .sorted { code(of: $0) < code(of: $1) }
        var ready: [String] = []
        var missing: [String] = []
        for language in all {
            let entry = "\(code(of: language))  \(displayName(of: language))"
            if await availability.status(from: language, to: nil) == .installed {
                ready.append(entry)
            } else {
                missing.append(entry)
            }
        }
        print("Installed (\(ready.count)):")
        ready.forEach { print("  " + $0) }
        print("\nSupported, not downloaded (\(missing.count)):")
        missing.forEach { print("  " + $0) }
        print("\nDownload more: System Settings > General > Language & Region > Translation Languages")
        exit(0)
    }

    /// The `?` query in Alfred: one row per language, so the download status is
    /// visible without opening a terminal.
    static func listRows() async -> Never {
        let all = deduplicated(await availability.supportedLanguages)
            .sorted { displayName(of: $0) < displayName(of: $1) }
        var rows: [Row] = []
        for language in all {
            let ready = await availability.status(from: language, to: nil) == .installed
            rows.append(Row(
                title: "\(displayName(of: language))  (\(code(of: language)))",
                subtitle: ready
                    ? "Downloaded — ready to translate"
                    : "Not downloaded — System Settings > General > Language & Region > Translation Languages",
                arg: ready ? code(of: language) : nil))
        }
        emit(rows, mode: .alfred)
    }

    static func readStdin() -> String {
        guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return "" }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func main() async {
        var options = parse(Array(CommandLine.arguments.dropFirst()))
        if options.list { await runList() }
        if options.text.isEmpty { options.text = readStdin() }

        if options.text == "?", options.mode == .alfred { await listRows() }

        guard !options.text.isEmpty else {
            emit([Row(title: "Type something to translate",
                      subtitle: "Direction is detected automatically. Prefix \">de\" to force a target, or type ? for the language list.",
                      arg: nil)],
                 mode: options.mode, failed: options.mode == .plain)
        }

        // Resolve source and target.
        let source: Locale.Language
        let target: Locale.Language
        let pair = options.pair ?? defaultPair()

        if let from = options.from, let to = options.to {
            (source, target) = (from, to)
        } else if let to = options.to {
            let candidates = deduplicated(await installed(await availability.supportedLanguages))
                .filter { code(of: $0) != code(of: to) }
            guard let detected = detect(options.text, among: candidates) else {
                emit([Row(title: "Could not detect the source language",
                          subtitle: "Pass --from to say what it is.", arg: nil)],
                     mode: options.mode, failed: true)
            }
            (source, target) = (detected, to)
        } else if let from = options.from {
            guard let other = pair.first(where: { code(of: $0) != code(of: from) }) else {
                emit([Row(title: "No target language",
                          subtitle: "Pass --to, or set OFFTRANSLATE_PAIR to include \(code(of: from)).", arg: nil)],
                     mode: options.mode, failed: true)
            }
            (source, target) = (from, other)
        } else {
            guard pair.count == 2 else {
                emit([Row(title: "Bad pair", subtitle: "Expected two languages, e.g. --pair en,pl", arg: nil)],
                     mode: options.mode, failed: true)
            }
            let detected = detect(options.text, among: pair) ?? pair[0]
            source = detected
            target = code(of: detected) == code(of: pair[0]) ? pair[1] : pair[0]
        }

        guard code(of: source) != code(of: target) else {
            emit([Row(title: options.text,
                      subtitle: "Source and target are both \(displayName(of: source)) — nothing to do.",
                      arg: options.text)],
                 mode: options.mode)
        }

        // Check the model is on disk before asking for a session.
        let direct = await availability.status(from: source, to: target)

        if direct != .installed {
            // Apple groups languages into families and only ships models within
            // them — Polish sits with en/ru/uk, German with the western set, so
            // pl → de has no direct model however many languages are downloaded.
            // Nearly everything pairs with English, so route through it.
            // Checked one at a time: `&&` short-circuits through an autoclosure,
            // which cannot carry an await.
            let english = Locale.Language(identifier: "en")
            var canPivot = code(of: source) != "en" && code(of: target) != "en"
            if canPivot {
                canPivot = await availability.status(from: source, to: english) == .installed
            }
            if canPivot {
                canPivot = await availability.status(from: english, to: target) == .installed
            }

            if canPivot {
                do {
                    let toEnglish = try await TranslationSession(installedSource: source, target: english)
                        .translate(options.text)
                    let toTarget = try await TranslationSession(installedSource: english, target: target)
                        .translate(toEnglish.targetText)
                    emit([Row(title: toTarget.targetText,
                              subtitle: "\(displayName(of: source)) → English → \(displayName(of: target))",
                              arg: toTarget.targetText)],
                         mode: options.mode)
                } catch {
                    emit([Row(title: "Translation failed",
                              subtitle: "\(error.localizedDescription)", arg: nil)],
                         mode: options.mode, failed: true)
                }
            }

            switch direct {
            case .supported:
                emit([Row(title: "\(displayName(of: source)) → \(displayName(of: target)) is not downloaded",
                          subtitle: "System Settings > General > Language & Region > Translation Languages",
                          arg: nil)],
                     mode: options.mode, failed: true)
            default:
                emit([Row(title: "\(displayName(of: source)) → \(displayName(of: target)) is not supported",
                          subtitle: "Run offtranslate --list to see what is available.", arg: nil)],
                     mode: options.mode, failed: true)
            }
        }

        do {
            let session = TranslationSession(installedSource: source, target: target)
            let response = try await session.translate(options.text)
            emit([Row(title: response.targetText,
                      subtitle: "\(displayName(of: source)) → \(displayName(of: target))",
                      arg: response.targetText)],
                 mode: options.mode)
        } catch {
            emit([Row(title: "Translation failed",
                      subtitle: "\(error.localizedDescription)", arg: nil)],
                 mode: options.mode, failed: true)
        }
    }
}
