import SwiftUI

struct SubmitView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                ScrollView {
                    VStack(spacing: AppSpacing.standard) {
                        supportHeader
                        unavailableCard
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.standard)
                    .padding(.bottom, AppSpacing.large)
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
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                Text(session.text("feedback"))
                    .font(.subheadline)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)

            ThemeToolbarButton(showLabel: false)
        }
        .cardSurface(padding: AppSpacing.large, cornerRadius: AppRadius.feature)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("feedback"), systemImage: "bubble.left.and.bubble.right.fill")
            Text(session.text("localSubmissionSaved"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(session.text("profileOnDevice"))
                .font(.subheadline)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Label(session.text("missingOpportunity"), systemImage: "magnifyingglass.circle.fill")
                Label(session.text("privacyPolicy"), systemImage: "lock.shield.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.outline(for: colorScheme))
            .accessibilityElement(children: .combine)

            Link(destination: AppLegalLinks.support) {
                Label(session.text("support"), systemImage: "arrow.up.right.square.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .secondary))

            Link(destination: AppLegalLinks.privacyPolicy) {
                Label(session.text("privacyPolicy"), systemImage: "lock.shield.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
        }
        .cardSurface()
    }
}
