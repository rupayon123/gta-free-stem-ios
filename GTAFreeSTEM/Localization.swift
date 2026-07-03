import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case fr
    case zh
    case yue
    case pa
    case ur
    case ta
    case tl
    case es
    case ar
    case fa
    case hi
    case pt
    case gu
    case bn
    case ja
    case ko
    case hu

    var id: String { rawValue }

    static let preferredLanguageDefaultsKey = "preferredLanguageCode"
    static let legacyPreferredLanguageDefaultsKey = "preferredLanguage"

    var localeIdentifier: String {
        switch self {
        case .zh: "zh-Hans"
        case .yue: "yue-Hant"
        case .pa: "pa"
        case .tl: "fil"
        case .pt: "pt"
        default: rawValue
        }
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .ar, .fa, .ur: .rightToLeft
        default: .leftToRight
        }
    }

    static func preferred(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let stored = defaults.string(forKey: preferredLanguageDefaultsKey),
           let language = matching(stored) {
            return language
        }
        if let legacy = defaults.string(forKey: legacyPreferredLanguageDefaultsKey),
           let language = matching(legacy) {
            return language
        }
        return preferredSystemLanguage(from: preferredLanguages)
    }

    static func preferredSystemLanguage(from preferredLanguages: [String]) -> AppLanguage {
        preferredLanguages.lazy.compactMap(matching(_:)).first ?? .en
    }

    static func normalized(_ value: String) -> AppLanguage {
        matching(value) ?? .en
    }

    private static func matching(_ value: String) -> AppLanguage? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        if let language = AppLanguage(rawValue: normalized) {
            return language
        }
        if let language = AppLanguage(rawValue: normalized.lowercased()) {
            return language
        }

        let legacy = normalized.lowercased()
        switch legacy {
        case "en-us", "en-ca", "en-gb": return .en
        case "fr-ca", "fr-fr": return .fr
        case "zh-hans", "zh-hant", "zh-cn", "zh-sg", "zh-tw", "zh-hk", "mandarin": return .zh
        case "yue-hant", "zh-yue", "cantonese", "cantonese/yue": return .yue
        case "pa-guru", "pa-in", "pa-ca": return .pa
        case "ur-pk", "ur-in": return .ur
        case "ta-in", "ta-lk": return .ta
        case "fil", "tl-ph", "tagalog", "tagalog/filipino", "filipino": return .tl
        case "es-mx", "es-es", "es-419": return .es
        case "ar-sa", "ar-eg", "ar-ae": return .ar
        case "fa-ir", "prs", "farsi", "persian", "farsi/persian": return .fa
        case "hi-in": return .hi
        case "pt-br", "pt-pt": return .pt
        case "gu-in": return .gu
        case "bn-bd", "bn-in": return .bn
        case "ja-jp": return .ja
        case "ko-kr": return .ko
        case "hu-hu": return .hu
        case "english": return .en
        case "french": return .fr
        case "punjabi": return .pa
        case "urdu": return .ur
        case "tamil": return .ta
        case "spanish": return .es
        case "arabic": return .ar
        case "hindi": return .hi
        case "portuguese": return .pt
        case "gujarati": return .gu
        case "bengali": return .bn
        case "japanese": return .ja
        case "korean": return .ko
        case "hungarian": return .hu
        default:
            guard let languageCode = legacy.split(separator: "-").first else {
                return nil
            }
            let primary = String(languageCode)
            if primary != legacy {
                return matching(primary)
            }
            return AppLanguage(rawValue: primary)
        }
    }
}

struct LanguageInfo: Sendable {
    let label: String
    let native: String
    let dir: String
}

enum AppResources {
    static func url(
        forResource name: String,
        withExtension ext: String,
        subdirectory: String? = nil,
        localization: String? = nil
    ) -> URL? {
        candidateBundles.lazy.compactMap {
            $0.url(forResource: name, withExtension: ext, subdirectory: subdirectory, localization: localization)
        }.first
    }

    static func path(
        forResource name: String,
        ofType ext: String,
        inDirectory subdirectory: String? = nil,
        forLocalization localization: String? = nil
    ) -> String? {
        url(forResource: name, withExtension: ext, subdirectory: subdirectory, localization: localization)?.path
    }

    private static var candidateBundles: [Bundle] {
        var seen = Set<String>()
        return ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            seen.insert(bundle.bundlePath).inserted
        }
    }
}

final class AppText: @unchecked Sendable {
    static let shared = AppText()

    private let meta: [String: LanguageInfo]
    private let strings: [String: [String: String]]

    private init() {
        guard
            let url = AppResources.url(forResource: "app_strings", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            meta = [:]
            strings = [:]
            return
        }

        let rawMeta = json["languageMeta"] as? [String: [String: String]] ?? [:]
        meta = rawMeta.mapValues { value in
            LanguageInfo(
                label: value["label"] ?? "",
                native: value["native"] ?? "",
                dir: value["dir"] ?? "ltr"
            )
        }

        strings = json.reduce(into: [String: [String: String]]()) { result, pair in
            guard pair.key != "languageMeta", let value = pair.value as? [String: String] else { return }
            result[pair.key] = value
        }
    }

    func string(_ key: String, language: AppLanguage) -> String {
        strings[language.rawValue]?[key] ?? strings[AppLanguage.en.rawValue]?[key] ?? key
    }

    func languageName(_ language: AppLanguage) -> String {
        guard let info = meta[language.rawValue] else { return language.rawValue }
        return "\(info.native) - \(info.label)"
    }
}
