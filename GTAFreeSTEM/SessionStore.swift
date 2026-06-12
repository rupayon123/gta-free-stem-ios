import AuthenticationServices
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var displayName = "Guest"
    @Published var apiToken: String?
    @Published var authMessage: String?
    @AppStorage("preferredLanguage") var preferredLanguage = "English"
    @AppStorage("preferredTheme") var preferredTheme = "System"

    var isSignedIn: Bool {
        apiToken?.isEmpty == false
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                displayName = credential.fullName?.givenName ?? "Apple user"
                authMessage = "Apple sign-in is ready. Connect the Rails OAuth callback before TestFlight."
            }
        case .failure(let error):
            authMessage = error.localizedDescription
        }
    }

    func signOut() {
        apiToken = nil
        displayName = "Guest"
    }
}
