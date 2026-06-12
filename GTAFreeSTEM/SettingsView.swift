import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var deleteMessage: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section(session.text("accountAdmin")) {
                    Text("\(session.text("signedInAs")) \(session.displayName)")
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        session.handleAppleSignIn(result)
                    }
                    .frame(height: 48)
                    Button(session.text("signOut"), role: .destructive) {
                        session.signOut()
                    }
                    Button(session.text("deleteAccount"), role: .destructive) {
                        Task { await deleteAccount() }
                    }
                }

                Section(session.text("siteLanguage")) {
                    Picker(session.text("siteLanguage"), selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(session.languageName(language)).tag(language.rawValue)
                        }
                    }
                    Picker(session.text("theme"), selection: $session.preferredTheme) {
                        Text(session.text("system")).tag("System")
                        Text(session.text("light")).tag("Light")
                        Text(session.text("dark")).tag("Dark")
                    }
                }

                Section(session.text("termsTitle")) {
                    NavigationLink(session.text("privacyPolicy")) {
                        LegalTextView(title: session.text("privacyPolicy"), bodyText: session.text("privacyBody"))
                    }
                    NavigationLink(session.text("termsTitle")) {
                        LegalTextView(title: session.text("termsTitle"), bodyText: session.text("termsBody"))
                    }
                }

                if let authMessage = session.authMessage {
                    Section {
                        Text(authMessage)
                    }
                }
                if let deleteMessage {
                    Section {
                        Text(deleteMessage)
                    }
                }
            }
            .navigationTitle(session.text("settings"))
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { session.preferredLanguageCode },
            set: { session.preferredLanguageCode = $0 }
        )
    }

    private func deleteAccount() async {
        do {
            try await api.deleteAccount(token: session.apiToken)
            session.signOut()
            deleteMessage = session.text("accountDeleted")
        } catch {
            deleteMessage = error.localizedDescription
        }
    }
}

struct LegalTextView: View {
    let title: String
    let bodyText: String

    var body: some View {
        ScrollView {
            Text(bodyText)
                .padding()
        }
        .navigationTitle(title)
    }
}
