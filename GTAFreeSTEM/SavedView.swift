import SwiftUI

struct SavedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                VStack(spacing: 20) {
                    Image(systemName: session.isSignedIn ? "bookmark.fill" : "lock.fill")
                        .font(.system(size: 50, weight: .black))
                        .foregroundStyle(Brand.coral)
                        .frame(width: 92, height: 92)
                        .background(Brand.sun, in: Circle())
                        .overlay {
                            Circle().stroke(Brand.outline(for: colorScheme), lineWidth: 3)
                        }

                    Text(session.isSignedIn ? session.text("savedEmpty") : session.text("signInToSave"))
                        .font(.title2.weight(.black))
                        .foregroundStyle(Brand.outline(for: colorScheme))
                        .multilineTextAlignment(.center)

                    Text(session.text("savedArchiveNote"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.mutedText(for: colorScheme))
                        .multilineTextAlignment(.center)

                    StickerBadge(text: session.text("saved"), color: Brand.sky, systemImage: "bookmark")
                }
                .frame(maxWidth: .infinity)
                .cardSurface(padding: 24, cornerRadius: 34)
                .padding()
            }
            .navigationTitle(session.text("saved"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ThemeToolbarButton()
                }
            }
        }
    }
}
