import SwiftUI

struct SubmitView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        supportHeader
                        unavailableCard
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(session.text("support"))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var supportHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.text("support"))
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                Text(session.text("feedback"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)

            ThemeToolbarButton(showLabel: false)
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("feedback"), systemImage: "bubble.left.and.bubble.right.fill")
            Text(session.text("localSubmissionSaved"))
                .font(.headline.weight(.bold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(session.text("appleReady"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Label(session.text("missingOpportunity"), systemImage: "magnifyingglass.circle.fill")
                Label(session.text("privacyPolicy"), systemImage: "lock.shield.fill")
            }
            .font(.subheadline.weight(.black))
            .foregroundStyle(Brand.outline(for: colorScheme))
            .accessibilityElement(children: .combine)
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }
}
