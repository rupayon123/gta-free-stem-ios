import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    @State private var deleteMessage: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        accountCard
                        savedCard
                        preferencesCard
                        legalCard
                        if let authMessage = session.authMessage {
                            messageCard(authMessage)
                        }
                        if let deleteMessage {
                            messageCard(deleteMessage)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(session.text("settings"))
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("accountAdmin"), systemImage: "person.crop.circle.fill")
            if session.isSignedIn {
                Text("\(session.text("signedInAs")) \(session.displayName)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Brand.outline(for: colorScheme))

                HStack(spacing: 10) {
                    Button(session.text("signOut"), role: .destructive) {
                        session.signOut()
                    }
                    .buttonStyle(StoryButtonStyle(kind: .quiet))

                    Button(session.text("deleteAccount"), role: .destructive) {
                        Task { await deleteAccount() }
                    }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                }
            } else {
                Text(session.text("appleReady"))
                    .font(.headline.weight(.black))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("saved"), systemImage: "bookmark.fill")
            Text(session.isSignedIn ? session.text("savedEmpty") : session.text("signInToSave"))
                .font(.headline.weight(.black))
                .foregroundStyle(Brand.outline(for: colorScheme))
            Text(session.text("savedArchiveNote"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mutedText(for: colorScheme))
            NavigationLink {
                SavedView()
            } label: {
                Label(session.text("saved"), systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .secondary))
        }
        .cardSurface(padding: 18, cornerRadius: 30)
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
                .font(.headline.weight(.black))
                .foregroundStyle(Brand.outline(for: colorScheme))
            Picker(session.text("theme"), selection: $session.preferredTheme) {
                Text(session.text("system")).tag("System")
                Text(session.text("light")).tag("Light")
                Text(session.text("dark")).tag("Dark")
            }
            .pickerStyle(.segmented)
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("termsTitle"), systemImage: "doc.text.fill")
            NavigationLink {
                LegalTextView(title: session.text("privacyPolicy"), bodyText: session.text("privacyBody"))
            } label: {
                Label(session.text("privacyPolicy"), systemImage: "lock.shield.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))

            NavigationLink {
                LegalTextView(title: session.text("termsTitle"), bodyText: session.text("termsBody"))
            } label: {
                Label(session.text("termsTitle"), systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(StoryButtonStyle(kind: .quiet))
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }

    private func messageCard(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.black))
            .foregroundStyle(Brand.outline(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 16, cornerRadius: 24)
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
            deleteMessage = session.text("serverResponseInvalid")
        }
    }
}

struct LegalTextView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let bodyText: String

    var body: some View {
        ZStack {
            StorybookBackground()
            ScrollView {
                Text(bodyText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.outline(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(padding: 18, cornerRadius: 28)
                    .padding()
            }
        }
        .navigationTitle(title)
    }
}
