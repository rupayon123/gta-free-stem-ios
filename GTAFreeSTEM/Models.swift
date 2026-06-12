import Foundation
import SwiftData

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
    let distanceKm: Double?
    let isNewFind: Bool?
    let sourceConfidence: String?
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

@Model
final class OpportunityCacheRecord {
    @Attribute(.unique) var cacheKey: String
    var payload: Data
    var updatedAt: Date

    init(cacheKey: String, payload: Data, updatedAt: Date = .now) {
        self.cacheKey = cacheKey
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class SavedHuntRecord {
    @Attribute(.unique) var cacheKey: String
    var query: String
    var modeRawValue: String
    var region: String
    var city: String
    var category: String
    var age: String
    var language: String
    var latitude: Double?
    var longitude: Double?
    var distanceKm: Double
    var sortRawValue: String
    var updatedAt: Date

    init(cacheKey: String, query: String, mode: SearchMode, filters: OpportunityFilters, updatedAt: Date = .now) {
        self.cacheKey = cacheKey
        self.query = query
        self.modeRawValue = mode.rawValue
        self.region = filters.region
        self.city = filters.city
        self.category = filters.category
        self.age = filters.age
        self.language = filters.language
        self.latitude = filters.latitude
        self.longitude = filters.longitude
        self.distanceKm = filters.distanceKm
        self.sortRawValue = filters.sort.rawValue
        self.updatedAt = updatedAt
    }
}

@Model
final class SeenOpportunityRecord {
    @Attribute(.unique) var opportunityID: String
    var firstSeenAt: Date
    var lastSeenAt: Date

    init(opportunityID: String, firstSeenAt: Date = .now, lastSeenAt: Date = .now) {
        self.opportunityID = opportunityID
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
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

    var textKey: String {
        switch self {
        case .all: "all"
        case .highSchool: "highSchool"
        case .volunteer: "volunteerHours"
        case .coop: "coop"
        case .mentorship: "mentorship"
        }
    }
}

enum SearchSort: String, CaseIterable, Identifiable {
    case date
    case distance
    case relevance

    var id: String { rawValue }

    var textKey: String {
        switch self {
        case .date: "sortSoonest"
        case .distance: "sortNearest"
        case .relevance: "sortBestMatch"
        }
    }
}

struct OpportunityFilters: Equatable {
    var region = "All"
    var city = ""
    var category = "All"
    var age = ""
    var language = "all"
    var latitude: Double?
    var longitude: Double?
    var distanceKm = 25.0
    var sort = SearchSort.date
    var includeNewFinds = true
    var blackFocused = false
    var girlsFocused = false
    var indigenousFocused = false
    var leadership = false

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    var hasActiveFilters: Bool {
        region != "All" ||
            !city.isEmpty ||
            category != "All" ||
            !age.isEmpty ||
            language != "all" ||
            hasLocation ||
            sort != .date ||
            !includeNewFinds ||
            blackFocused ||
            girlsFocused ||
            indigenousFocused ||
            leadership
    }
}

enum BrowseDisplayMode: String, CaseIterable, Identifiable {
    case list
    case map

    var id: String { rawValue }

    var textKey: String {
        switch self {
        case .list: "list"
        case .map: "map"
        }
    }
}
