import SwiftUI

struct SubmitView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    @State private var feedback = FeedbackDraft()
    @State private var missing = MissingOpportunityDraft()
    @State private var message: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            ZStack {
                StorybookBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        feedbackCard
                        missingCard
                        if let message {
                            Text(message)
                                .font(.headline.weight(.black))
                                .foregroundStyle(Brand.outline(for: colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardSurface(padding: 16, cornerRadius: 24)
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(session.text("support"))
        }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("feedback"), systemImage: "bubble.left.and.bubble.right.fill")
            TextField(session.text("name"), text: $feedback.name)
                .storyField()
            TextField(session.text("email"), text: $feedback.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .storyField()
            TextField(session.text("whatNeedsFixing"), text: $feedback.message, axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .storyField()
            Button {
                Task { await sendFeedback() }
            } label: {
                Label(session.text("sendFeedback"), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .primary))
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }

    private var missingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionTitle(text: session.text("missingOpportunity"), systemImage: "magnifyingglass.circle.fill")
            TextField(session.text("listingTitle"), text: $missing.title)
                .storyField()
            TextField(session.text("hostOrgName"), text: $missing.organization)
                .storyField()
            TextField(session.text("city"), text: $missing.city)
                .storyField()
            TextField(session.text("sourceLink"), text: $missing.sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .storyField()
            TextField(session.text("notes"), text: $missing.notes, axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .storyField()
            Button {
                Task { await submitMissing() }
            } label: {
                Label(session.text("submitOpportunity"), systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StoryButtonStyle(kind: .secondary))
        }
        .cardSurface(padding: 18, cornerRadius: 30)
    }

    private func sendFeedback() async {
        do {
            try await api.sendFeedback(feedback, token: session.apiToken)
            message = session.text("feedbackSent")
        } catch {
            saveLocalPreview(kind: "feedback", payload: ["name": feedback.name, "email": feedback.email, "message": feedback.message])
            message = session.text("localSubmissionSaved")
        }
    }

    private func submitMissing() async {
        do {
            try await api.submitMissingOpportunity(missing, token: session.apiToken)
            message = session.text("submissionSent")
        } catch {
            saveLocalPreview(kind: "missing", payload: [
                "title": missing.title,
                "organization": missing.organization,
                "city": missing.city,
                "sourceURL": missing.sourceURL,
                "notes": missing.notes
            ])
            message = session.text("localSubmissionSaved")
        }
    }

    private func saveLocalPreview(kind: String, payload: [String: String]) {
        let key = "previewSubmissions"
        let existing = UserDefaults.standard.array(forKey: key) as? [[String: String]] ?? []
        let item = payload.merging(["kind": kind, "createdAt": ISO8601DateFormatter().string(from: Date())]) { current, _ in current }
        UserDefaults.standard.set(existing + [item], forKey: key)
    }
}
