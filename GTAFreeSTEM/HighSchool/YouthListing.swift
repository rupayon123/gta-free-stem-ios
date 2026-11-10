import Foundation

/// Independent curated youth records. No feed, app UI, storage or network activation.
enum YouthHub {
    enum ValidationError: Error, Equatable { case invalid(String) }
    enum ListingKind: String, Codable, Sendable { case event, role, program, providerDirectory = "provider-directory", resource }
    enum Pathway: String, Codable, Sendable { case volunteer, learning, leadershipCareers = "leadership-careers", funding }
    enum Status: String, Codable, Sendable { case open, closed, upcoming, unknown, conflicting }
    enum CostStatus: String, Codable, Sendable { case noFee = "no-fee-evidence", required = "required-cost", unknown }
    enum AudienceContext: String, Codable, Sendable { case highSchool = "high-school", teen, adult, childWithAdult = "child-with-adult", allAges = "all-ages", unknown }
    enum ReviewStatus: String, Codable, Sendable { case approved, hold }
    enum HoursStatus: String, Codable, Sendable { case notStated = "not-stated", providerStated = "provider-stated" }
    enum Delivery: String, Codable, Sendable { case inPerson = "in-person", virtual, hybrid, unknown }
    struct Audience: Codable, Sendable {
        var context: AudienceContext
        var original: String
        var ageMin: Double?
        var ageMax: Double?
        var grades: [Int]?
        var residency: String?
        var restrictions: [String]?
    }
    struct RequiredCost: Codable, Sendable {
        var description: String
        var mandatory: Bool
        var amount: Double?
        var currency: String?
    }
    struct Cost: Codable, Sendable { var status: CostStatus; var original: String; var requiredCosts: [RequiredCost] }
    struct Availability: Codable, Sendable {
        var status: Status
        var original: String
        var conflicting: Bool
        var opensAt: String?
        var closesAt: String?
        var seasonEndsOn: String?
    }
    struct Hours: Codable, Sendable { var status: HoursStatus; var minutes: Int?; var original: String? }
    struct Listing: Codable, Sendable {
        var schemaVersion: Int
        var id: String
        var listingKind: ListingKind
        var pathway: Pathway
        var title: String
        var provider: String
        var sourceUrl: String
        var checkedAt: String
        var reviewStatus: ReviewStatus
        var audience: Audience
        var cost: Cost
        var availability: Availability
        var hours: Hours
        var regions: [String]?
        var delivery: Delivery?
        var commitmentOriginal: String?
    }
    struct EvaluationContext: Codable, Sendable {
        var now: String
        var selectedAge: Double? = nil
        var selectedGrade: Int? = nil
        var maxEvidenceAgeDays: Double? = nil
    }
    struct Evaluation: Sendable {
        var teenHub: Bool
        var reviewed: Bool
        var selectedAgeEligible: Bool?
        var selectedGradeEligible: Bool?
        var directorySection: Bool
        var volunteerRole: Bool
        var verifiedFreeRoles: Bool
        var verifiedFreePrograms: Bool
        var freeBadge: Bool
        var effectiveStatus: Status
        var evidenceCurrent: Bool
        var statusLabel: String
        var costLabel: String
        var applyNow: Bool
        var ageMin: Double?
        var ageMax: Double?
        var providerHours: Double?
        var restrictions: [String]
        var residency: String?
        let schoolApproved = false
        let autoCredit = 0
        let inferUserIdentity = false
        let inventDate = false
        let inventHours = false
        let mapPin = false

        /// Portable wire output includes explicit null, matching the TS goldens.
        func jsonData() throws -> Data {
            func value<T>(_ optional: T?) -> Any { if let optional { return optional }; return NSNull() }
            return try JSONSerialization.data(withJSONObject: [
                "teenHub": teenHub, "reviewed": reviewed,
                "selectedAgeEligible": value(selectedAgeEligible), "selectedGradeEligible": value(selectedGradeEligible),
                "directorySection": directorySection, "volunteerRole": volunteerRole,
                "verifiedFreeRoles": verifiedFreeRoles, "verifiedFreePrograms": verifiedFreePrograms,
                "freeBadge": freeBadge, "effectiveStatus": effectiveStatus.rawValue, "evidenceCurrent": evidenceCurrent,
                "statusLabel": statusLabel, "costLabel": costLabel, "applyNow": applyNow,
                "schoolApproved": schoolApproved, "autoCredit": autoCredit, "inferUserIdentity": inferUserIdentity,
                "inventDate": inventDate, "inventHours": inventHours, "mapPin": mapPin,
                "ageMin": value(ageMin), "ageMax": value(ageMax), "providerHours": value(providerHours),
                "restrictions": restrictions, "residency": value(residency)
            ])
        }
    }

    static func require(_ condition: Bool, _ field: String) throws {
        guard condition else { throw ValidationError.invalid(field) }
    }
    static func text(_ value: String, max: Int = 2000, empty: Bool = false) -> Bool {
        // ECMAScript WhiteSpace + LineTerminator; U+0085 is deliberately not trim.
        let trim = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        return value.utf16.count <= max && (empty || !value.trimmingCharacters(in: trim).isEmpty)
    }
    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
    static func validLocalDate(_ value: String) -> Bool {
        guard matches(value, #"^\d{4}-\d{2}-\d{2}$"#) else { return false }
        let p = value.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1900...9999).contains(p[0]), (1...12).contains(p[1]) else { return false }
        let leap = p[0] % 4 == 0 && (p[0] % 100 != 0 || p[0] % 400 == 0)
        return p[2] >= 1 && p[2] <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][p[1] - 1]
    }
    static func timestamp(_ value: String) -> Date? {
        guard matches(value, #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,3})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$"#), validLocalDate(String(value.prefix(10))) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value)
    }
    static func safeSourceURL(_ value: String) -> Bool {
        guard value.utf16.count <= 2048, let u = URLComponents(string: value),
              u.scheme?.lowercased() == "https", u.user == nil, u.password == nil,
              u.port == nil || u.port == 443, let rawHost = u.host?.lowercased(), rawHost.contains(".") else { return false }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        guard !host.contains(":"), !matches(host, #"^[\d.]+$"#),
              !host.split(separator: ".").allSatisfy({ matches(String($0), #"^(?:\d+|0x[0-9a-f]+)$"#) }) else { return false }
        return !["localhost", "local", "internal", "lan", "home", "invalid", "test"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Optional nulls are rejected on the wire, matching TS undefined-only optionals.
    static func rejectNulls(_ object: Any) throws {
        if object is NSNull { throw ValidationError.invalid("null input") }
        if let dictionary = object as? [String: Any] { for value in dictionary.values { try rejectNulls(value) } }
        if let array = object as? [Any] { for value in array { try rejectNulls(value) } }
    }
    static func decodeCatalogue(_ data: Data) throws -> [Listing] {
        let object = try JSONSerialization.jsonObject(with: data)
        // Codable accepts explicit null for optionals, while TS only accepts absence.
        // Unknown listing metadata is ignored by both implementations, including null.
        func optionalFields(_ object: Any?, _ keys: [String]) throws {
            guard let dictionary = object as? [String: Any] else { return }
            for key in keys { try require(!(dictionary[key] is NSNull), "null " + key) }
        }
        if let rows = object as? [[String: Any]] {
            for row in rows {
                try optionalFields(row, ["regions", "delivery", "commitmentOriginal"])
                try optionalFields(row["audience"], ["ageMin", "ageMax", "grades", "residency", "restrictions"])
                try optionalFields(row["availability"], ["opensAt", "closesAt", "seasonEndsOn"])
                try optionalFields(row["hours"], ["minutes", "original"])
                if let cost = row["cost"] as? [String: Any], let costs = cost["requiredCosts"] as? [[String: Any]] {
                    for item in costs { try optionalFields(item, ["amount", "currency"]) }
                }
            }
        }
        let rows = try JSONDecoder().decode([Listing].self, from: data)
        try require(rows.count <= 2000 && Set(rows.map(\.id)).count == rows.count, "catalogue IDs/count")
        for row in rows { try validate(row) }
        return rows
    }
    static func validate(_ x: Listing) throws {
        try require(x.schemaVersion == 1 && text(x.id, max: 120), "version/id")
        try require(text(x.title, max: 240) && text(x.provider, max: 240) && safeSourceURL(x.sourceUrl), "source")
        try require(timestamp(x.checkedAt) != nil, "review date")
        let a = x.audience
        try require(text(a.original), "audience original")
        for age in [a.ageMin, a.ageMax].compactMap({ $0 }) { try require(age.isFinite && age >= 0 && age <= 120, "age") }
        if let min = a.ageMin, let max = a.ageMax { try require(min <= max, "age bounds") }
        if let grades = a.grades { try require(!grades.isEmpty && grades.count <= 13 && Set(grades).count == grades.count && grades.allSatisfy { (0...12).contains($0) }, "grades") }
        if let residency = a.residency { try require(text(residency), "residency") }
        if let restrictions = a.restrictions { try require(restrictions.count <= 20 && restrictions.allSatisfy { text($0) }, "restrictions") }
        try require(text(x.cost.original) && x.cost.requiredCosts.count <= 20, "cost")
        for c in x.cost.requiredCosts {
            try require(text(c.description), "required cost")
            if let amount = c.amount { try require(amount.isFinite && amount >= 0, "cost amount") }
            if let currency = c.currency { try require(matches(currency, #"^[A-Z]{3}$"#), "currency") }
        }
        let v = x.availability
        try require(text(v.original), "availability original")
        for date in [v.opensAt, v.closesAt].compactMap({ $0 }) { try require(timestamp(date) != nil, "application date") }
        if let start = v.opensAt, let end = v.closesAt, let s = timestamp(start), let e = timestamp(end) { try require(s < e, "application interval") }
        if let end = v.seasonEndsOn { try require(validLocalDate(end), "season") }
        if let minutes = x.hours.minutes { try require(x.hours.status == .providerStated && minutes > 0 && minutes <= 9_007_199_254_740_991, "provider minutes") }
        if x.hours.status == .providerStated { try require(x.hours.original.map { text($0) } ?? false, "hours original") }
        if let regions = x.regions { try require(regions.count <= 5 && regions.allSatisfy { ["Toronto", "York", "Peel", "Durham", "Halton"].contains($0) }, "regions") }
        if let commitment = x.commitmentOriginal { try require(text(commitment), "commitment") }
    }

    static func evaluate(_ row: Listing, context: EvaluationContext) throws -> Evaluation {
        try validate(row)
        guard let now = timestamp(context.now), let checked = timestamp(row.checkedAt) else { throw ValidationError.invalid("clock") }
        if let age = context.selectedAge { try require(age.isFinite && age >= 0 && age <= 120, "selected age") }
        if let grade = context.selectedGrade { try require((0...12).contains(grade), "selected grade") }
        let maxDays = context.maxEvidenceAgeDays ?? 30
        try require(maxDays.isFinite && maxDays > 0 && maxDays <= 90, "evidence age")
        let elapsed = now.timeIntervalSince(checked)
        let current = elapsed >= 0 && elapsed <= maxDays * 86400
        let reviewed = current && row.reviewStatus == .approved
        let a = row.audience
        let ageEligible: Bool? = context.selectedAge.flatMap { age in
            a.ageMin == nil && a.ageMax == nil ? nil : (a.ageMin.map { age >= $0 } ?? true) && (a.ageMax.map { age <= $0 } ?? true)
        }
        let gradeEligible: Bool? = context.selectedGrade.flatMap { grade in a.grades.map { $0.contains(grade) } }
        let relevant = a.context == .highSchool || a.context == .teen ||
            (a.context != .adult && a.context != .childWithAdult && (a.grades?.contains { (9...12).contains($0) } ?? false))
        let teenHub = reviewed && relevant && ageEligible != false && gradeEligible != false
        let resource = row.listingKind == .providerDirectory || row.listingKind == .resource
        let f = DateFormatter(); f.locale = Locale(identifier: "en_CA"); f.timeZone = TimeZone(identifier: "America/Toronto"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: now)
        var status = row.availability.status
        if !reviewed { status = .unknown }
        else if row.availability.conflicting || status == .conflicting { status = .conflicting }
        else if row.availability.closesAt.flatMap(timestamp).map({ now >= $0 }) == true || row.availability.seasonEndsOn.map({ $0 < today }) == true { status = .closed }
        else if status != .closed && row.availability.opensAt.flatMap(timestamp).map({ now < $0 }) == true { status = .upcoming }
        else if status == .upcoming { status = .unknown }
        let mandatory = row.cost.requiredCosts.filter(\.mandatory)
        let cost: CostStatus = row.cost.status == .required || mandatory.contains { ($0.amount ?? 0) > 0 } ? .required : mandatory.contains { $0.amount == nil } ? .unknown : row.cost.status
        let free = teenHub && !resource && cost == .noFee && (status == .open || status == .upcoming)
        let volunteerRole = row.listingKind == .role && row.pathway == .volunteer
        var statusLabel = status == .closed ? "Closed" : status == .open ? "Open" : "Confirm with provider"
        if status == .upcoming, let date = row.availability.opensAt.flatMap(timestamp) { f.dateFormat = "MMMM d"; statusLabel = "Opens " + f.string(from: date) }
        return Evaluation(teenHub: teenHub, reviewed: reviewed, selectedAgeEligible: ageEligible, selectedGradeEligible: gradeEligible,
                          directorySection: reviewed && row.listingKind == .providerDirectory, volunteerRole: volunteerRole,
                          verifiedFreeRoles: free && volunteerRole && status == .open, verifiedFreePrograms: free && !volunteerRole && status == .open,
                          freeBadge: free, effectiveStatus: status, evidenceCurrent: current, statusLabel: statusLabel,
                          costLabel: cost == .required ? "Required cost" : cost == .unknown ? "Cost unknown" : "No fee evidenced",
                          applyNow: teenHub && !resource && status == .open && cost == .noFee,
                          ageMin: a.ageMin, ageMax: a.ageMax, providerHours: row.hours.minutes.map { Double($0) / 60 }, restrictions: a.restrictions ?? [], residency: a.residency)
    }
}
