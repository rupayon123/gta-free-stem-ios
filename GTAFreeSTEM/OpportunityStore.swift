import Foundation

@MainActor
final class OpportunityStore: ObservableObject {
    @Published var query = ""
    @Published var mode: SearchMode = .all
    @Published var filters = OpportunityFilters()
    @Published var opportunities: [Opportunity] = []
    @Published var activeCount = 0
    @Published var lastUpdated: String?
    @Published var dataSourceLabel = "Rails API"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.opportunities(query: query, mode: mode, filters: filters)
            apply(response, source: "Rails API")
            errorMessage = nil
        } catch {
            do {
                let response = try LocalOpportunitySnapshot.load(query: query, mode: mode, filters: filters)
                apply(response, source: "Preview database")
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func resetFilters() {
        filters = OpportunityFilters()
    }

    func save(_ opportunity: Opportunity, token: String?) async {
        do {
            try await api.save(opportunityID: opportunity.id, token: token)
            errorMessage = "Saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ response: OpportunityListResponse, source: String) {
        opportunities = response.data
        activeCount = response.meta?.activeCount ?? response.data.count
        lastUpdated = response.meta?.lastUpdated
        dataSourceLabel = source
    }
}
