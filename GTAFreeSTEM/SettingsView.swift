import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var deleteMessage: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text("Signed in as \(session.displayName)")
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        session.handleAppleSignIn(result)
                    }
                    .frame(height: 48)
                    Button("Sign Out", role: .destructive) {
                        session.signOut()
                    }
                    Button("Delete Account", role: .destructive) {
                        Task { await deleteAccount() }
                    }
                }

                Section("Preferences") {
                    Picker("Language", selection: $session.preferredLanguage) {
                        ForEach(["English", "French", "Mandarin", "Cantonese", "Punjabi", "Urdu", "Tamil", "Tagalog", "Spanish", "Arabic", "Farsi", "Hindi", "Gujarati", "Bengali", "Japanese", "Korean", "Hungarian"], id: \.self) {
                            Text($0)
                        }
                    }
                    Picker("Theme", selection: $session.preferredTheme) {
                        ForEach(["System", "Light", "Dark"], id: \.self) {
                            Text($0)
                        }
                    }
                }

                Section("Privacy") {
                    NavigationLink("Privacy Policy") { LegalTextView(title: "Privacy", bodyText: "Browsing is public. Accounts are only for saves, feedback, submissions, and account deletion.") }
                    NavigationLink("Terms") { LegalTextView(title: "Terms", bodyText: "Listings link to public provider pages. No ads, paid ranking, direct messaging, or tutoring marketplace features are included.") }
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
            .navigationTitle("Settings")
        }
    }

    private func deleteAccount() async {
        do {
            try await api.deleteAccount(token: session.apiToken)
            session.signOut()
            deleteMessage = "Account deleted."
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
