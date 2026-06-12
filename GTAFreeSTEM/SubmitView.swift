import SwiftUI

struct SubmitView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var feedback = FeedbackDraft()
    @State private var missing = MissingOpportunityDraft()
    @State private var message: String?
    private let api = APIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section(session.text("feedback")) {
                    TextField(session.text("name"), text: $feedback.name)
                    TextField(session.text("email"), text: $feedback.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField(session.text("whatNeedsFixing"), text: $feedback.message, axis: .vertical)
                    Button(session.text("sendFeedback")) {
                        Task { await sendFeedback() }
                    }
                }
                Section(session.text("missingOpportunity")) {
                    TextField(session.text("listingTitle"), text: $missing.title)
                    TextField(session.text("hostOrgName"), text: $missing.organization)
                    TextField(session.text("city"), text: $missing.city)
                    TextField(session.text("sourceLink"), text: $missing.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField(session.text("notes"), text: $missing.notes, axis: .vertical)
                    Button(session.text("submitOpportunity")) {
                        Task { await submitMissing() }
                    }
                }
                if let message {
                    Section {
                        Text(message)
                    }
                }
            }
            .navigationTitle(session.text("support"))
        }
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
