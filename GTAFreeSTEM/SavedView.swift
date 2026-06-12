import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: session.isSignedIn ? "bookmark.fill" : "lock")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Brand.blue)
                Text(session.isSignedIn ? "Saved opportunities will appear here." : "Sign in to save opportunities.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Expired saved listings stay available in your archive so you can remember what you found.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .cardSurface()
            .padding()
            .navigationTitle("Saved")
        }
    }
}
