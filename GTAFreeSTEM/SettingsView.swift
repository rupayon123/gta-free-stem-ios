import SwiftUI
import SwiftData

enum AppLegalLinks {
    static let privacyPolicy = URL(string: "https://gta-free-stem.vercel.app/privacy/")!
    static let termsOfUse = URL(string: "https://gta-free-stem.vercel.app/terms/")!
    static let support = URL(string: "https://gta-free-stem.vercel.app/support/")!
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var opportunities: OpportunityStore
    @State private var profileNameDraft = ""
    @State private var accountMessage: String?
    @State private var profileEditorPresented = false
    @State private var deleteConfirmationPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                ScrollView {
                    VStack(spacing: AppSpacing.standard) {
                        accountCard
                        savedCard
                        preferencesCard
                        legalCard
                        if let accountMessage {
                            messageCard(accountMessage)
                        }
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.standard)
                    .padding(.bottom, AppSpacing.large)
                }
            }
            .navigationTitle(session.text("settings"))
        }
        .sheet(isPresented: $profileEditorPresented) {
            profileEditor
        }
        .confirmationDialog(
            session.text("deleteAccount"),
            isPresented: $deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(session.text("deleteAccount"), role: .destructive) {
                deleteLocalProfileAndSaves()
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            StorySectionTitle(text: session.text("account"), systemImage: "person.crop.circle.fill")
            if session.hasLocalProfile {
                Text("\(session.text("name")): \(session.displayName)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))

                Text(session.text("profileOnDevice"))
                    .font(.subheadline)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        signOutButton
                        deleteAccountButton
                    }

                    VStack(spacing: 10) {
                        signOutButton
                        deleteAccountButton
                    }
                }
            } else {
                Text(session.text("guest"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(session.text("profileOnDevice"))
                    .font(.subheadline)
                    .foregroundStyle(Brand.mutedText(for: colorScheme))

                Button(session.text("account")) {
                    profileNameDraft = ""
                    profileEditorPresented = true
                }
                .buttonStyle(StoryButtonStyle(kind: .secondary))
            }
        }
        .cardSurface()
    }

    private var signOutButton: some View {
        Button {
            clearLocalProfileOnly()
        } label: {
            Text(session.text("signOut"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .quiet))
    }

    private var deleteAccountButton: some View {
        Button(role: .destructive) {
            deleteConfirmationPresented = true
        } label: {
            Text(session.text("deleteAccount"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StoryButtonStyle(kind: .destructive))
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("saved"), systemImage: "bookmark.fill")
            Text(session.text("savedEmpty"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
            Text(session.text("savedArchiveNote"))
                .font(.subheadline)
                .foregroundStyle(Brand.mutedText(for: colorScheme))
            NavigationLink {
                SavedView()
            } label: {
                Label(session.text("saved"), systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .secondary))
        }
        .cardSurface()
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("siteLanguage"), systemImage: "globe")
            Picker(session.text("siteLanguage"), selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(session.languageName(language)).tag(language.rawValue)
                }
            }
            .pickerStyle(.navigationLink)
            .storyPickerRow()

            Text(session.text("theme"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Brand.outline(for: colorScheme))
            Picker(session.text("theme"), selection: $session.preferredTheme) {
                Text(session.text("system")).tag("System")
                Text(session.text("light")).tag("Light")
                Text(session.text("dark")).tag("Dark")
            }
            .pickerStyle(.segmented)
        }
        .cardSurface()
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("termsTitle"), systemImage: "doc.text.fill")
            Text("\(session.text("profileOnDevice")) \(session.text("localSubmissionSaved"))")
                .font(.subheadline)
                .foregroundStyle(Brand.mutedText(for: colorScheme))

            Link(destination: AppLegalLinks.privacyPolicy) {
                Label(session.text("privacyPolicy"), systemImage: "lock.shield.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))

            Link(destination: AppLegalLinks.termsOfUse) {
                Label(session.text("termsTitle"), systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))

            Link(destination: AppLegalLinks.support) {
                Label(session.text("support"), systemImage: "questionmark.bubble.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
        }
        .cardSurface()
    }

    private func messageCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Brand.outline(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { session.preferredLanguageCode },
            set: { session.preferredLanguageCode = $0 }
        )
    }

    private var profileEditor: some View {
        NavigationStack {
            Form {
                Section(session.text("account")) {
                    TextField(session.text("name"), text: $profileNameDraft)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                }
            }
            .tint(Brand.lake)
            .navigationTitle(session.text("account"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(session.text("done")) {
                        session.saveLocalProfile(named: profileNameDraft)
                        accountMessage = nil
                        profileEditorPresented = false
                    }
                    .disabled(profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func deleteLocalProfileAndSaves() {
        clearLocalProfileAndSaves()
    }

    private func clearLocalProfileOnly() {
        session.clearLocalProfile()
        accountMessage = nil
    }

    private func clearLocalProfileAndSaves() {
        Task {
            do {
                try SavedOpportunityLibrary.deleteAll(in: modelContext)
                try await opportunities.clearPersonalHistory(in: modelContext)
                session.clearLocalProfile()
                accountMessage = session.text("accountDeleted")
            } catch {
                accountMessage = session.text("serverResponseInvalid")
            }
        }
    }
}
