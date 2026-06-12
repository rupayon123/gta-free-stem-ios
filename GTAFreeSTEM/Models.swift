import Foundation

struct Opportunity: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let organization: String
    let description: String
    let summary: String?
    let category: String
    let city: String
    let region: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let startDate: String?
    let endDate: String?
    let deadline: String?
    let ageMin: Int
    let ageMax: Int?
    let language: [String]
    let cost: String
    let sourceUrl: String
    let registrationUrl: String?
    let status: String
    let volunteerHoursEligible: Bool
    let coopEligible: Bool
    let tags: [String]
}

struct OpportunityListResponse: Codable {
    struct Metadata: Codable {
        let activeCount: Int?
        let lastUpdated: String?
    }

    let data: [Opportunity]
    let meta: Metadata?
}

struct OpportunityResponse: Codable {
    let data: Opportunity
}

struct APIStatusResponse: Codable {
    struct Payload: Codable {
        let id: Int?
        let status: String?
        let deleted: Bool?
    }

    let data: Payload
}

struct FeedbackDraft {
    var name = ""
    var email = ""
    var message = ""
}

struct MissingOpportunityDraft {
    var title = ""
    var organization = ""
    var city = ""
    var sourceURL = ""
    var notes = ""
}

enum SearchMode: String, CaseIterable, Identifiable {
    case all = "All"
    case highSchool = "High School"
    case volunteer = "Volunteer Hours"
    case coop = "Co-op / SHSM"
    case mentorship = "Mentorship"

    var id: String { rawValue }
}
