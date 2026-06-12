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

    static func normalized(_ value: String) -> AppLanguage {
        if let language = AppLanguage(rawValue: value) {
            return language
        }

        let legacy = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch legacy {
        case "english": return .en
        case "french": return .fr
        case "mandarin": return .zh
        case "cantonese", "cantonese/yue": return .yue
        case "punjabi": return .pa
        case "urdu": return .ur
        case "tamil": return .ta
        case "tagalog", "tagalog/filipino", "filipino": return .tl
        case "spanish": return .es
        case "arabic": return .ar
        case "farsi", "persian", "farsi/persian": return .fa
        case "hindi": return .hi
        case "portuguese": return .pt
        case "gujarati": return .gu
        case "bengali": return .bn
        case "japanese": return .ja
        case "korean": return .ko
        case "hungarian": return .hu
        default: return .en
        }
    }
}

struct LanguageInfo: Sendable {
    let label: String
    let native: String
    let dir: String
}

final class AppText: @unchecked Sendable {
    static let shared = AppText()

    private let meta: [String: LanguageInfo]
    private let strings: [String: [String: String]]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "app_strings", withExtension: "json"),
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
