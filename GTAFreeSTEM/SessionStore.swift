import AuthenticationServices
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var displayName = AppText.shared.string("guest", language: .en)
    @Published var apiToken: String?
    @Published var authMessage: String?
    @Published var preferredLanguageCode: String {
        didSet {
            let normalized = AppLanguage.normalized(preferredLanguageCode).rawValue
            if preferredLanguageCode != normalized {
                preferredLanguageCode = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.languageKey)
            if apiToken == nil {
                displayName = AppText.shared.string("guest", language: AppLanguage.normalized(normalized))
            }
        }
    }
    @Published var preferredTheme: String {
        didSet {
            if !["System", "Light", "Dark"].contains(preferredTheme) {
                preferredTheme = "System"
            }
            UserDefaults.standard.set(preferredTheme, forKey: Self.themeKey)
        }
    }

    private static let languageKey = "preferredLanguageCode"
    private static let legacyLanguageKey = "preferredLanguage"
    private static let themeKey = "preferredTheme"

    init() {
        let storedCode = UserDefaults.standard.string(forKey: Self.languageKey)
        let legacyLanguage = UserDefaults.standard.string(forKey: Self.legacyLanguageKey)
        preferredLanguageCode = AppLanguage.normalized(storedCode ?? legacyLanguage ?? AppLanguage.en.rawValue).rawValue
        preferredTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? "Light"
        displayName = text("guest")
    }

    var isSignedIn: Bool {
        apiToken?.isEmpty == false
    }

    var language: AppLanguage {
        AppLanguage.normalized(preferredLanguageCode)
    }

    var colorScheme: ColorScheme? {
        switch preferredTheme {
        case "Light": .light
        case "Dark": .dark
        default: nil
        }
    }

    func text(_ key: String) -> String {
        AppText.shared.string(key, language: language)
    }

    func languageName(_ language: AppLanguage) -> String {
        AppText.shared.languageName(language)
    }

    func title(for opportunity: Opportunity) -> String {
        opportunity.localizedTitle(language: language)
    }

    func organization(for opportunity: Opportunity) -> String {
        opportunity.localizedOrganization(language: language)
    }

    func city(for opportunity: Opportunity) -> String {
        opportunity.localizedCity(language: language)
    }

    func region(for opportunity: Opportunity) -> String {
        opportunity.localizedRegion(language: language)
    }

    func categoryName(for opportunity: Opportunity) -> String {
        let localizedCategory = opportunity.localizedCategory(language: language)
        return localizedCategory == opportunity.category ? categoryName(opportunity.category) : localizedCategory
    }

    func cost(for opportunity: Opportunity) -> String {
        let localizedCost = opportunity.localizedCost(language: language)
        return localizedCost.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("free") == .orderedSame ? text("freeAccessible") : localizedCost
    }

    func categoryName(_ category: String) -> String {
        let key = "category" + category
            .replacingOccurrences(of: "&", with: "And")
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        let localized = text(key)
        return localized == key ? category : localized
    }

    func summary(for opportunity: Opportunity) -> String {
        let summary = opportunity.localizedSummary(language: language)
        guard language != .en else { return summary }
        guard !opportunity.hasTranslation(for: language) else { return summary }
        let template = text("summaryTemplate")
        guard template != "summaryTemplate" else { return summary }
        let ages = opportunity.ageMax.map { "\(opportunity.ageMin)-\($0)" } ?? "\(opportunity.ageMin)+"
        return template
            .replacingOccurrences(of: "{summary}", with: summary)
            .replacingOccurrences(of: "{category}", with: categoryName(for: opportunity))
            .replacingOccurrences(of: "{provider}", with: organization(for: opportunity))
            .replacingOccurrences(of: "{city}", with: city(for: opportunity))
            .replacingOccurrences(of: "{ages}", with: ages)
    }

    func formattedDate(_ value: String?) -> String {
        guard let value else { return "" }
        let candidates = Self.isoDateFormatters.compactMap { $0.date(from: value) }
        guard let date = candidates.first else { return value }
        return Self.displayDateFormatter(for: language).string(from: date)
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                displayName = credential.fullName?.givenName ?? text("appleUser")
                authMessage = text("appleReady")
            }
        case .failure:
            authMessage = text("serverResponseInvalid")
        }
    }

    func signOut() {
        apiToken = nil
        displayName = text("guest")
    }

    private static let isoDateFormatters: [ISO8601DateFormatter] = {
        let options: [[ISO8601DateFormatter.Options]] = [
            [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone, .withColonSeparatorInTimeZone],
            [.withInternetDateTime, .withFractionalSeconds]
        ]

        return options.map {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = $0.reduce(into: ISO8601DateFormatter.Options()) { combined, option in
                combined.insert(option)
            }
            return formatter
        }
    }()

    private static func displayDateFormatter(for language: AppLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: language.localeIdentifier)
        return formatter
    }
}
