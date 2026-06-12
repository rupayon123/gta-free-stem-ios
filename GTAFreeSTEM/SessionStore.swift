import AuthenticationServices
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var displayName = "Guest"
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
        preferredTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? "System"
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

    func summary(for opportunity: Opportunity) -> String {
        let summary = opportunity.summary ?? opportunity.description
        guard language != .en else { return summary }
        let template = text("summaryTemplate")
        guard template != "summaryTemplate" else { return summary }
        let ages = opportunity.ageMax.map { "\(opportunity.ageMin)-\($0)" } ?? "\(opportunity.ageMin)+"
        return template
            .replacingOccurrences(of: "{summary}", with: summary)
            .replacingOccurrences(of: "{category}", with: opportunity.category)
            .replacingOccurrences(of: "{provider}", with: opportunity.organization)
            .replacingOccurrences(of: "{city}", with: opportunity.city)
            .replacingOccurrences(of: "{ages}", with: ages)
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                displayName = credential.fullName?.givenName ?? "Apple user"
                authMessage = text("appleReady")
            }
        case .failure(let error):
            authMessage = error.localizedDescription
        }
    }

    func signOut() {
        apiToken = nil
        displayName = text("guest")
    }
}
