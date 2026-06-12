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
                Section("Feedback") {
                    TextField("Name", text: $feedback.name)
                    TextField("Email", text: $feedback.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("What should be fixed?", text: $feedback.message, axis: .vertical)
                    Button("Send Feedback") {
                        Task { await sendFeedback() }
                    }
                }
                Section("Missing Opportunity") {
                    TextField("Title", text: $missing.title)
                    TextField("Organization", text: $missing.organization)
                    TextField("City", text: $missing.city)
                    TextField("Source link", text: $missing.sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("Notes", text: $missing.notes, axis: .vertical)
                    Button("Submit Opportunity") {
                        Task { await submitMissing() }
                    }
                }
                if let message {
                    Section {
                        Text(message)
                    }
                }
            }
            .navigationTitle("Support")
        }
    }

    private func sendFeedback() async {
        do {
            try await api.sendFeedback(feedback, token: session.apiToken)
            message = "Feedback sent."
        } catch {
            message = error.localizedDescription
        }
    }

    private func submitMissing() async {
        do {
            try await api.submitMissingOpportunity(missing, token: session.apiToken)
            message = "Submission sent."
        } catch {
            message = error.localizedDescription
        }
    }
}
