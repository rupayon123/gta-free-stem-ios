import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: session.isSignedIn ? "bookmark.fill" : "lock")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Brand.blue)
                Text(session.isSignedIn ? session.text("savedEmpty") : session.text("signInToSave"))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(session.text("savedArchiveNote"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .cardSurface()
            .padding()
            .navigationTitle(session.text("saved"))
        }
    }
}
