import Foundation
import SwiftData
#if os(iOS) && !targetEnvironment(macCatalyst)
@preconcurrency import WatchConnectivity
#endif

enum ExternalOpportunityURL {
    static func make(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        // Provider data occasionally contains an old HTTP link that redirects to
        // HTTPS. The app never hands an insecure or custom-scheme link to the OS.
        components.scheme = "https"
        return components.url
    }
}

enum OpportunityCoordinate {
    static func isValid(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude,
              let longitude,
              latitude.isFinite,
              longitude.isFinite
        else {
            return false
        }

        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

enum OpportunityCostEligibility {
    private static let zeroCostPhrases: Set<String> = [
        "no charge",
        "no cost",
        "no fee",
        "no fees",
        "zero charge",
        "zero cost",
        "zero fee"
    ]

    static func isExplicitlyFree(_ rawCost: String?) -> Bool {
        guard let cost = normalizedCost(rawCost) else { return false }
        guard !containsPaidQualifier(cost) else { return false }

        return cost == "free" ||
            cost.hasPrefix("free ") ||
            cost == "complimentary" ||
            zeroCostPhrases.contains(cost) ||
            isExplicitZeroAmount(cost)
    }

    private static func normalizedCost(_ rawCost: String?) -> String? {
        guard let rawCost else { return nil }
        let normalized = rawCost
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized.isEmpty ? nil : normalized
    }

    private static func containsPaidQualifier(_ cost: String) -> Bool {
        let paidPhrases = [
            "paid",
            "payment",
            "tuition",
            "purchase",
            "subscription",
            "free trial",
            "fee applies",
            "fees apply",
            "fee required",
            "fees required",
            "charge applies",
            "charges apply",
            "cost applies",
            "cost required"
        ]
        guard !paidPhrases.contains(where: cost.contains) else { return true }

        let nonZeroAmountPattern = #"(?:[$£€¥₹]\s*(?:0*[1-9]\d*|0*[.,]\d*[1-9]\d*)|\b(?:cad|usd|eur|gbp)\s*(?:0*[1-9]\d*|0*[.,]\d*[1-9]\d*)\b|\b(?:0*[1-9]\d*|0*[.,]\d*[1-9]\d*)\s*(?:cad|usd|eur|gbp|dollars?)\b)"#
        return cost.range(of: nonZeroAmountPattern, options: .regularExpression) != nil
    }

    private static func isExplicitZeroAmount(_ cost: String) -> Bool {
        let zeroAmountPattern = #"^(?:[$£€¥₹]\s*0(?:[.,]0{1,2})?|(?:cad|usd|eur|gbp)\s*0(?:[.,]0{1,2})?|0(?:[.,]0{1,2})?\s*(?:cad|usd|eur|gbp|dollars?)?)$"#
        return cost.range(of: zeroAmountPattern, options: .regularExpression) != nil
    }
}

enum FeedPublicationRevision {
    static func date(from raw: String?) -> Date? {
        guard let raw, raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"#, options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let value = formatter.date(from: raw), value.timeIntervalSince1970 > 0,
              formatter.string(from: value) == raw else { return nil }
        return value
    }
}

struct OpportunityTranslation: Codable, Hashable, Sendable {
    let title: String?
    let organization: String?
    let description: String?
    let summary: String?
    let category: String?
    let city: String?
    let region: String?
    let address: String?
    let cost: String?
    let tags: [String]?

    private enum CodingKeys: String, CodingKey {
        case title
        case organization
        case provider
        case description
        case summary
        case category
        case city
        case region
        case address
        case cost
        case tags
    }

    init(
        title: String? = nil,
        organization: String? = nil,
        description: String? = nil,
        summary: String? = nil,
        category: String? = nil,
        city: String? = nil,
        region: String? = nil,
        address: String? = nil,
        cost: String? = nil,
        tags: [String]? = nil
    ) {
        self.title = title
        self.organization = organization
        self.description = description
        self.summary = summary
        self.category = category
        self.city = city
        self.region = region
        self.address = address
        self.cost = cost
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        organization =
            (try? container.decodeIfPresent(String.self, forKey: .organization)) ??
            (try? container.decodeIfPresent(String.self, forKey: .provider))
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        city = try? container.decodeIfPresent(String.self, forKey: .city)
        region = try? container.decodeIfPresent(String.self, forKey: .region)
        address = try? container.decodeIfPresent(String.self, forKey: .address)
        cost = try? container.decodeIfPresent(String.self, forKey: .cost)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(organization, forKey: .organization)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(cost, forKey: .cost)
        try container.encodeIfPresent(tags, forKey: .tags)
    }

    var hasContent: Bool {
        [
            title,
            organization,
            description,
            summary,
            category,
            city,
            region,
            address,
            cost
        ].contains { Self.nonEmpty($0) != nil } || tags?.contains { Self.nonEmpty($0) != nil } == true
    }

    func merged(with fallback: OpportunityTranslation?) -> OpportunityTranslation {
        guard let fallback else { return self }
        let mergedTags = Self.nonEmptyList(tags) ?? Self.nonEmptyList(fallback.tags)
        return OpportunityTranslation(
            title: Self.preferredValue(title, fallback: fallback.title),
            organization: Self.preferredValue(organization, fallback: fallback.organization),
            description: Self.preferredValue(description, fallback: fallback.description),
            summary: Self.preferredValue(summary, fallback: fallback.summary),
            category: Self.preferredValue(category, fallback: fallback.category),
            city: Self.preferredValue(city, fallback: fallback.city),
            region: Self.preferredValue(region, fallback: fallback.region),
            address: Self.preferredValue(address, fallback: fallback.address),
            cost: Self.preferredValue(cost, fallback: fallback.cost),
            tags: mergedTags
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func preferredValue(_ value: String?, fallback: String?) -> String? {
        if let preferred = nonEmpty(value) {
            return preferred
        }
        return nonEmpty(fallback)
    }

    private static func nonEmptyList(_ values: [String]?) -> [String]? {
        let cleaned = values?.compactMap(nonEmpty)
        return (cleaned?.isEmpty == false) ? cleaned : nil
    }
}

struct Opportunity: Identifiable, Codable, Hashable, Sendable {
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
    let translations: [String: OpportunityTranslation]
    let virtual: Bool

    var isExplicitlyFree: Bool {
        OpportunityCostEligibility.isExplicitlyFree(cost)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case organization
        case provider
        case description
        case summary
        case category
        case categories
        case city
        case region
        case address
        case latitude
        case longitude
        case startDate
        case endDate
        case deadline
        case ageMin
        case ageMax
        case ages
        case language
        case languages
        case cost
        case sourceUrl
        case registrationUrl
        case status
        case volunteerHoursEligible
        case coopEligible
        case tags
        case distanceKm
        case isNewFind
        case sourceConfidence
        case translations
        case localizations
        case localized
        case virtual
    }

    private enum AgeKeys: String, CodingKey {
        case min
        case max
    }

    init(
        id: String,
        title: String,
        organization: String,
        description: String,
        summary: String?,
        category: String,
        city: String,
        region: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        startDate: String?,
        endDate: String?,
        deadline: String?,
        ageMin: Int,
        ageMax: Int?,
        language: [String],
        cost: String,
        sourceUrl: String,
        registrationUrl: String?,
        status: String,
        volunteerHoursEligible: Bool,
        coopEligible: Bool,
        tags: [String],
        distanceKm: Double?,
        isNewFind: Bool?,
        sourceConfidence: String?,
        translations: [String: OpportunityTranslation] = [:],
        virtual: Bool = false
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.description = description
        self.summary = summary
        self.category = category
        self.city = city
        self.region = region
        self.address = address
        if OpportunityCoordinate.isValid(latitude: latitude, longitude: longitude) {
            self.latitude = latitude
            self.longitude = longitude
        } else {
            self.latitude = nil
            self.longitude = nil
        }
        self.startDate = startDate
        self.endDate = endDate
        self.deadline = deadline
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.language = language
        self.cost = cost
        self.sourceUrl = sourceUrl
        self.registrationUrl = registrationUrl
        self.status = status
        self.volunteerHoursEligible = volunteerHoursEligible
        self.coopEligible = coopEligible
        self.tags = tags
        self.distanceKm = distanceKm
        self.isNewFind = isNewFind
        self.sourceConfidence = sourceConfidence
        self.translations = Self.normalizedTranslations(translations)
        self.virtual = virtual
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let categories = (try? container.decode([String].self, forKey: .categories)) ?? []
        let fallbackSummary = try? container.decode(String.self, forKey: .summary)

        var decodedAgeMin = (try? container.decode(Int.self, forKey: .ageMin)) ?? 0
        var decodedAgeMax = try? container.decodeIfPresent(Int.self, forKey: .ageMax)
        if let ages = try? container.nestedContainer(keyedBy: AgeKeys.self, forKey: .ages) {
            decodedAgeMin = (try? ages.decode(Int.self, forKey: .min)) ?? decodedAgeMin
            decodedAgeMax = (try? ages.decodeIfPresent(Int.self, forKey: .max)) ?? decodedAgeMax
        }

        let decodedTitle = try container.decode(String.self, forKey: .title)
        let decodedOrganization =
            (try? container.decode(String.self, forKey: .organization)) ??
            (try? container.decode(String.self, forKey: .provider)) ??
            "Community provider"
        let decodedDescription =
            (try? container.decode(String.self, forKey: .description)) ??
            fallbackSummary ??
            decodedTitle
        let decodedCategory =
            (try? container.decode(String.self, forKey: .category)) ??
            categories.first ??
            "STEM"
        let decodedLanguage =
            (try? container.decode([String].self, forKey: .language)) ??
            (try? container.decode([String].self, forKey: .languages)) ??
            ["en"]
        let decodedSourceURL =
            (try? container.decode(String.self, forKey: .sourceUrl)) ??
            (try? container.decode(String.self, forKey: .registrationUrl)) ??
            ""
        let decodedTranslations =
            (try? container.decode([String: OpportunityTranslation].self, forKey: .translations)) ??
            (try? container.decode([String: OpportunityTranslation].self, forKey: .localizations)) ??
            (try? container.decode([String: OpportunityTranslation].self, forKey: .localized)) ??
            [:]
        let decodedCost = try? container.decodeIfPresent(String.self, forKey: .cost)
        let decodedStartDate = try Self.decodeScheduleDate(from: container, forKey: .startDate)
        let decodedEndDate = try Self.decodeScheduleDate(from: container, forKey: .endDate)
        let decodedDeadline = try Self.decodeScheduleDate(from: container, forKey: .deadline)
        let decodedStatus: String
        if container.contains(.status) {
            decodedStatus = try container.decode(String.self, forKey: .status)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decodedStatus.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "A supplied opportunity status must not be blank.")
            }
        } else {
            decodedStatus = "active"
        }

        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: decodedTitle,
            organization: decodedOrganization,
            description: decodedDescription,
            summary: fallbackSummary,
            category: decodedCategory,
            city: (try? container.decode(String.self, forKey: .city)) ?? "GTA",
            region: (try? container.decode(String.self, forKey: .region)) ?? "All",
            address: try? container.decodeIfPresent(String.self, forKey: .address),
            latitude: try? container.decodeIfPresent(Double.self, forKey: .latitude),
            longitude: try? container.decodeIfPresent(Double.self, forKey: .longitude),
            startDate: decodedStartDate,
            endDate: decodedEndDate,
            deadline: decodedDeadline,
            ageMin: decodedAgeMin,
            ageMax: decodedAgeMax,
            language: decodedLanguage,
            cost: decodedCost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            sourceUrl: decodedSourceURL,
            registrationUrl: try? container.decodeIfPresent(String.self, forKey: .registrationUrl),
            status: decodedStatus,
            volunteerHoursEligible: (try? container.decode(Bool.self, forKey: .volunteerHoursEligible)) ?? false,
            coopEligible: (try? container.decode(Bool.self, forKey: .coopEligible)) ?? false,
            tags: (try? container.decode([String].self, forKey: .tags)) ?? categories,
            distanceKm: try? container.decodeIfPresent(Double.self, forKey: .distanceKm),
            isNewFind: try? container.decodeIfPresent(Bool.self, forKey: .isNewFind),
            sourceConfidence: try? container.decodeIfPresent(String.self, forKey: .sourceConfidence),
            translations: decodedTranslations,
            virtual: try container.decodeIfPresent(Bool.self, forKey: .virtual) ?? false
        )
    }

    private static func decodeScheduleDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        guard container.contains(key) else { return nil }
        if try container.decodeNil(forKey: key) { return nil }
        let value = try container.decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        guard scheduleDateValidator.isValid(value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A supplied opportunity date must be a valid calendar date or ISO 8601 timestamp.")
        }
        return value
    }

    private static let scheduleDateValidator = ScheduleDateValidator()

    /// Reuse parsers while decoding a full feed, without sharing mutable formatters unsafely.
    private final class ScheduleDateValidator: @unchecked Sendable {
        private let lock = NSLock()
        private let dateOnly: DateFormatter
        private let timestamp: ISO8601DateFormatter
        private let fractionalTimestamp: ISO8601DateFormatter

        init() {
            let dateOnly = DateFormatter()
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            dateOnly.dateFormat = "yyyy-MM-dd"
            dateOnly.isLenient = false
            self.dateOnly = dateOnly
            let timestamp = ISO8601DateFormatter()
            timestamp.formatOptions = [.withInternetDateTime]
            self.timestamp = timestamp
            let fractionalTimestamp = ISO8601DateFormatter()
            fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.fractionalTimestamp = fractionalTimestamp
        }

        func isValid(_ value: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let day = String(value.prefix(10))
            guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  let parsedDay = dateOnly.date(from: day), dateOnly.string(from: parsedDay) == day
            else { return false }
            if value.count == 10 { return true }
            guard value.range(of: #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return false }
            return fractionalTimestamp.date(from: value) != nil || timestamp.date(from: value) != nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(organization, forKey: .organization)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(category, forKey: .category)
        try container.encode(city, forKey: .city)
        try container.encode(region, forKey: .region)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encode(ageMin, forKey: .ageMin)
        try container.encodeIfPresent(ageMax, forKey: .ageMax)
        try container.encode(language, forKey: .language)
        try container.encode(cost, forKey: .cost)
        try container.encode(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(registrationUrl, forKey: .registrationUrl)
        try container.encode(status, forKey: .status)
        try container.encode(virtual, forKey: .virtual)
        try container.encode(volunteerHoursEligible, forKey: .volunteerHoursEligible)
        try container.encode(coopEligible, forKey: .coopEligible)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try container.encodeIfPresent(isNewFind, forKey: .isNewFind)
        try container.encodeIfPresent(sourceConfidence, forKey: .sourceConfidence)
        if !translations.isEmpty {
            try container.encode(translations, forKey: .translations)
        }
    }

    func translation(for language: AppLanguage) -> OpportunityTranslation? {
        let candidates = [
            language.rawValue,
            language.localeIdentifier,
            language.localeIdentifier.lowercased()
        ]
        for candidate in candidates {
            if let translation = translations[candidate], translation.hasContent {
                return translation
            }
        }

        return translations.first {
            AppLanguage.supportedLanguage(for: $0.key) == language && $0.value.hasContent
        }?.value
    }

    func hasTranslation(for language: AppLanguage) -> Bool {
        translation(for: language) != nil
    }

    func replacingStatus(with newStatus: String) -> Opportunity {
        Opportunity(
            id: id,
            title: title,
            organization: organization,
            description: description,
            summary: summary,
            category: category,
            city: city,
            region: region,
            address: address,
            latitude: latitude,
            longitude: longitude,
            startDate: startDate,
            endDate: endDate,
            deadline: deadline,
            ageMin: ageMin,
            ageMax: ageMax,
            language: language,
            cost: cost,
            sourceUrl: sourceUrl,
            registrationUrl: registrationUrl,
            status: newStatus,
            volunteerHoursEligible: volunteerHoursEligible,
            coopEligible: coopEligible,
            tags: tags,
            distanceKm: distanceKm,
            isNewFind: isNewFind,
            sourceConfidence: sourceConfidence,
            translations: translations,
            virtual: virtual
        )
    }

    func localizedTitle(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.title], fallback: title)
    }

    func localizedOrganization(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.organization], fallback: organization)
    }

    func localizedDescription(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.description], fallback: description)
    }

    func localizedSummary(language: AppLanguage) -> String {
        let selectedTranslation = translation(for: language)
        let resolvedSummary = Self.localizedValue(
            [selectedTranslation?.summary, selectedTranslation?.description, summary, description],
            fallback: description
        )
        guard language != .en else { return resolvedSummary }
        guard selectedTranslation == nil else { return resolvedSummary }
        return localizedTemplateSummary(
            baseSummary: resolvedSummary,
            category: localizedCategoryName(language: language),
            provider: localizedOrganization(language: language),
            city: localizedCity(language: language),
            language: language,
            ages: ageMax.map { "\(ageMin)-\($0)" } ?? "\(ageMin)+"
        )
    }

    func localizedCategory(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.category], fallback: category)
    }

    func localizedCity(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.city], fallback: city)
    }

    func localizedRegion(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.region], fallback: region)
    }

    func localizedAddress(language: AppLanguage) -> String? {
        Self.localizedValue([translation(for: language)?.address, address])
    }

    func localizedCost(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.cost], fallback: cost)
    }

    func localizedTags(language: AppLanguage) -> [String] {
        let translatedTags = translation(for: language)?.tags?.compactMap(Self.nonEmpty) ?? []
        return translatedTags.isEmpty ? tags : translatedTags
    }

    private static func normalizedTranslations(_ translations: [String: OpportunityTranslation]) -> [String: OpportunityTranslation] {
        translations.reduce(into: [String: OpportunityTranslation]()) { result, pair in
            guard pair.value.hasContent else { return }
            let trimmedKey = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { return }
            result[trimmedKey] = pair.value
            if let supportedLanguage = AppLanguage.supportedLanguage(for: trimmedKey) {
                result[supportedLanguage.rawValue] = pair.value
            }
        }
    }

    private func localizedTemplateSummary(
        baseSummary: String,
        category: String,
        provider: String,
        city: String,
        language: AppLanguage,
        ages: String
    ) -> String {
        let template = AppText.shared.string("summaryTemplate", language: language)
        guard template != "summaryTemplate" else { return baseSummary }
        let resolved = template
            .replacingOccurrences(of: "{summary}", with: baseSummary)
            .replacingOccurrences(of: "{category}", with: category)
            .replacingOccurrences(of: "{provider}", with: provider)
            .replacingOccurrences(of: "{city}", with: city)
            .replacingOccurrences(of: "{ages}", with: ages)
        return resolved.contains(baseSummary) ? resolved : "\(resolved)\n\(baseSummary)"
    }

    private func localizedCategoryName(language: AppLanguage) -> String {
        let key = "category" +
            category
            .replacingOccurrences(of: "&", with: "And")
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        let localized = AppText.shared.string(key, language: language)
        return localized == key ? category : localized
    }

    private static func localizedValue(_ values: [String?], fallback: String) -> String {
        localizedValue(values) ?? fallback
    }

    private static func localizedValue(_ values: [String?]) -> String? {
        values.lazy.compactMap(nonEmpty).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct OpportunityListResponse: Codable, Sendable {
    struct Metadata: Codable, Sendable {
        let activeCount: Int?
        let lastUpdated: String?
    }

    struct SourceHealth: Codable, Sendable {
        struct Library: Codable, Sendable {
            let status: String?
            let attemptedPages: Int?
            let successfulPages: Int?
            let pageSuccessRatio: Double?
            let minimumPageSuccessRatio: Double?
            let acceptedListings: Int?
            let minimumAcceptedListings: Int?
        }

        struct Discovery: Codable, Sendable {
            let status: String?
            let sourcesChecked: Int?
            let successfulSources: Int?
            let sourceSuccessRatio: Double?
            let minimumSourceSuccessRatio: Double?
        }

        let library: Library?
        let discovery: Discovery?

        func isHealthy(forPublishedCount publishedCount: Int) -> Bool {
            guard
                let library,
                let discovery,
                library.status?.lowercased() == "healthy",
                discovery.status?.lowercased() == "healthy",
                let attemptedPages = library.attemptedPages,
                attemptedPages > 0,
                let successfulPages = library.successfulPages,
                successfulPages > 0,
                successfulPages <= attemptedPages,
                let pageSuccessRatio = library.pageSuccessRatio,
                let minimumPageSuccessRatio = library.minimumPageSuccessRatio,
                pageSuccessRatio.isFinite,
                pageSuccessRatio > 0, pageSuccessRatio <= 1,
                minimumPageSuccessRatio.isFinite,
                minimumPageSuccessRatio > 0, minimumPageSuccessRatio <= 1,
                pageSuccessRatio >= minimumPageSuccessRatio,
                Double(successfulPages) / Double(attemptedPages) >= minimumPageSuccessRatio,
                let acceptedListings = library.acceptedListings,
                let minimumAcceptedListings = library.minimumAcceptedListings,
                minimumAcceptedListings > 0,
                acceptedListings >= minimumAcceptedListings,
                publishedCount >= minimumAcceptedListings,
                let sourcesChecked = discovery.sourcesChecked,
                sourcesChecked > 0,
                let successfulSources = discovery.successfulSources,
                successfulSources > 0,
                successfulSources <= sourcesChecked,
                let sourceSuccessRatio = discovery.sourceSuccessRatio,
                let minimumSourceSuccessRatio = discovery.minimumSourceSuccessRatio,
                sourceSuccessRatio.isFinite,
                sourceSuccessRatio > 0, sourceSuccessRatio <= 1,
                minimumSourceSuccessRatio.isFinite,
                minimumSourceSuccessRatio > 0, minimumSourceSuccessRatio <= 1,
                sourceSuccessRatio >= minimumSourceSuccessRatio,
                Double(successfulSources) / Double(sourcesChecked) >= minimumSourceSuccessRatio
            else {
                return false
            }
            return true
        }
    }

    struct ContentRights: Codable, Sendable {
        struct OwnerPermission: Codable, Sendable {
            let confirmationID: String
            let confirmedAt: String
            let scope: [String]
        }

        struct Source: Codable, Sendable {
            let organization: String
            let sourceHost: String
            let records: Int
            let status: String
            let basisUrl: String
            let conditions: [String]
            let termsVerifiedAt: String
            let termsVersion: String
            let termsDigestVersion: String
            let termsSectionDigest: String
            let ownerPermission: OwnerPermission?

            private enum CodingKeys: String, CodingKey {
                case organization, sourceHost, records, status, basisUrl, conditions
                case termsVerifiedAt, termsVersion, termsDigestVersion, termsSectionDigest, ownerPermission
            }

            init(organization: String, sourceHost: String, records: Int, status: String,
                 basisUrl: String = "", conditions: [String] = [], termsVerifiedAt: String = "",
                 termsVersion: String = "", termsDigestVersion: String = "", termsSectionDigest: String = "",
                 ownerPermission: OwnerPermission? = nil) {
                self.organization = organization
                self.sourceHost = sourceHost
                self.records = records
                self.status = status
                self.basisUrl = basisUrl
                self.conditions = conditions
                self.termsVerifiedAt = termsVerifiedAt
                self.termsVersion = termsVersion
                self.termsDigestVersion = termsDigestVersion
                self.termsSectionDigest = termsSectionDigest
                self.ownerPermission = ownerPermission
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                organization = try c.decode(String.self, forKey: .organization)
                sourceHost = try c.decode(String.self, forKey: .sourceHost)
                records = try c.decode(Int.self, forKey: .records)
                status = try c.decode(String.self, forKey: .status)
                basisUrl = try c.decodeIfPresent(String.self, forKey: .basisUrl) ?? ""
                conditions = try c.decodeIfPresent([String].self, forKey: .conditions) ?? []
                termsVerifiedAt = try c.decodeIfPresent(String.self, forKey: .termsVerifiedAt) ?? ""
                termsVersion = try c.decodeIfPresent(String.self, forKey: .termsVersion) ?? ""
                termsDigestVersion = try c.decodeIfPresent(String.self, forKey: .termsDigestVersion) ?? ""
                termsSectionDigest = try c.decodeIfPresent(String.self, forKey: .termsSectionDigest) ?? ""
                ownerPermission = try c.decodeIfPresent(OwnerPermission.self, forKey: .ownerPermission)
            }
        }

        let termsVerifiedAt: String
        let sources: [Source]
        let restrictedOpportunityIDs: [String]?

        private enum CodingKeys: String, CodingKey {
            case termsVerifiedAt
            case sources
            case restrictedOpportunityIDs = "restrictedOpportunityIds"
        }

        private struct ApprovedTermsEvidence {
            let basisURL: String
            let termsVersion: String
            let termsSectionDigest: String
        }

        private static let termsDigestVersion = "bibliocommons-relevant-sections-v1"
        private static let termsConditions = [
            "Automated access uses the provider's RSS/XML event feed.",
            "Every displayed extract links to its original BiblioCommons event page.",
            "GTA FREE STEM is free and does not monetize provider content."
        ]
        private static let approvedTermsEvidence: [String: ApprovedTermsEvidence] = [
            "Markham Public Library\u{001F}markham.bibliocommons.com": ApprovedTermsEvidence(
                basisURL: "https://markham.bibliocommons.com/info/terms/",
                termsVersion: "2018-09-19",
                termsSectionDigest: "sha256:451e63466c801166653f47336e236d05f9a50a3df45a917fa603e92bcd11c8a0"
            ),
            "Toronto Public Library\u{001F}tpl.bibliocommons.com": ApprovedTermsEvidence(
                basisURL: "https://tpl.bibliocommons.com/info/terms/",
                termsVersion: "2018-09-19",
                termsSectionDigest: "sha256:c9b14cbd531afa09533e844274bb9f07f8042883e12b5a3990be3100ca5d4b43"
            )
        ]

        private static func approvedTermsEvidence(
            for key: String,
            source: Source
        ) -> ApprovedTermsEvidence? {
            if let approved = approvedTermsEvidence[key] {
                return approved
            }
#if DEBUG
            // Unit-test feeds use URLProtocol with example.com. This branch is
            // compiled out of App Store archives; production providers must
            // always match the explicit binary allowlist above.
            if source.sourceHost.lowercased() == "example.com",
               source.basisUrl == "https://example.com/terms/" {
                return ApprovedTermsEvidence(
                    basisURL: source.basisUrl,
                    termsVersion: "2018-09-19",
                    termsSectionDigest: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
                )
            }
#endif
            return nil
        }

        func isReleaseReady(
            for opportunities: [Opportunity],
            feedUpdated: String?,
            now: Date
        ) -> Bool {
            guard let verifiedDate = FeedFreshness.date(from: termsVerifiedAt),
                  FeedFreshness.isCurrent(termsVerifiedAt, now: now),
                  let feedDate = FeedFreshness.date(from: feedUpdated),
                  !sources.isEmpty,
                  let restrictedOpportunityIDs
            else {
                return false
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            let verifiedDay = calendar.startOfDay(for: verifiedDate)
            let feedDay = calendar.startOfDay(for: feedDate)
            guard verifiedDay >= feedDay else { return false }

            let normalizedRestrictedIDs = restrictedOpportunityIDs.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard normalizedRestrictedIDs.allSatisfy({ !$0.isEmpty }),
                  Set(normalizedRestrictedIDs).count == normalizedRestrictedIDs.count,
                  Set(normalizedRestrictedIDs).isDisjoint(with: Set(opportunities.map(\.id)))
            else {
                return false
            }

            var declaredCounts = [String: Int]()
            for source in sources {
                let organization = source.organization.trimmingCharacters(in: .whitespacesAndNewlines)
                let declaredHost = source.sourceHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let key = "\(organization)\u{001F}\(declaredHost)"
                if source.status == "owner-confirmed-permission" {
                    // Owner confirmation is a distinct basis, not an assertion
                    // that a written agreement or new terms digest was received.
                    guard !organization.isEmpty, !declaredHost.isEmpty, source.records > 0,
                          Self.approvedTermsEvidence[key] != nil,
                          let permission = source.ownerPermission,
                          permission.confirmationID == "gta-library-content-2026-10-25",
                          permission.confirmedAt == "2026-10-25",
                          permission.scope == ["display-event-listings", "translate-event-listings"]
                    else { return false }
                } else {
                    guard !organization.isEmpty,
                          !declaredHost.isEmpty,
                          source.records > 0,
                          source.status == "terms-permitted",
                          let approved = Self.approvedTermsEvidence(for: key, source: source),
                          source.basisUrl == approved.basisURL,
                          source.termsVersion == approved.termsVersion,
                          source.termsDigestVersion == Self.termsDigestVersion,
                          source.termsSectionDigest == approved.termsSectionDigest,
                          source.conditions == Self.termsConditions,
                          let basisURL = URL(string: source.basisUrl),
                          basisURL.scheme?.lowercased() == "https",
                          basisURL.host?.lowercased() == declaredHost,
                          let sourceVerifiedDate = FeedFreshness.date(from: source.termsVerifiedAt),
                          calendar.startOfDay(for: sourceVerifiedDate) >= feedDay,
                          calendar.startOfDay(for: sourceVerifiedDate) == verifiedDay
                    else {
                        return false
                    }
                }
                guard declaredCounts[key] == nil else { return false }
                declaredCounts[key] = source.records
            }

            var observedCounts = [String: Int]()
            for opportunity in opportunities {
                guard let sourceURL = URL(string: opportunity.sourceUrl),
                      sourceURL.scheme?.lowercased() == "https",
                      let sourceHost = sourceURL.host?.lowercased(),
                      opportunity.registrationUrl == opportunity.sourceUrl
                else {
                    return false
                }
                let key = "\(opportunity.organization)\u{001F}\(sourceHost)"
                guard declaredCounts[key] != nil else { return false }
                observedCounts[key, default: 0] += 1
            }
            return observedCounts == declaredCounts
        }
    }

    let data: [Opportunity]
    let meta: Metadata?
    let sourceHealth: SourceHealth?
    let contentRights: ContentRights?
    let publicationRevision: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case opportunities
        case meta
        case count
        case lastDataChange
        case sourceHealth
        case contentRights
        case publicationRevision
    }

    init(
        data: [Opportunity],
        meta: Metadata?,
        sourceHealth: SourceHealth? = nil,
        contentRights: ContentRights? = nil,
        publicationRevision: String? = nil
    ) {
        let eligibleData = data.filter(\.isExplicitlyFree)
        self.data = eligibleData
        self.meta = meta.map {
            Metadata(activeCount: eligibleData.count, lastUpdated: $0.lastUpdated)
        }
        self.sourceHealth = sourceHealth
        self.contentRights = contentRights
        self.publicationRevision = publicationRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedData: [Opportunity]
        if container.contains(.data) {
            decodedData = try container.decode([Opportunity].self, forKey: .data)
        } else if container.contains(.opportunities) {
            decodedData = try container.decode([Opportunity].self, forKey: .opportunities)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.data,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "The public opportunity feed must contain either data or opportunities."
                )
            )
        }
        if let declaredCount = try container.decodeIfPresent(Int.self, forKey: .count), declaredCount != decodedData.count {
            throw DecodingError.dataCorruptedError(
                forKey: .count,
                in: container,
                debugDescription: "The declared opportunity count does not match the payload."
            )
        }
        let decodedMeta = try? container.decode(Metadata.self, forKey: .meta)
        let feedUpdated = try? container.decode(String.self, forKey: .lastDataChange)
        let decodedSourceHealth = try container.decodeIfPresent(SourceHealth.self, forKey: .sourceHealth)
        let decodedContentRights = try container.decodeIfPresent(ContentRights.self, forKey: .contentRights)

        let eligibleData = decodedData.filter(\.isExplicitlyFree)
        data = eligibleData
        meta = Metadata(
            activeCount: eligibleData.count,
            lastUpdated: decodedMeta?.lastUpdated ?? feedUpdated
        )
        sourceHealth = decodedSourceHealth
        contentRights = decodedContentRights
        if container.contains(.publicationRevision) {
            let raw = try container.decode(String.self, forKey: .publicationRevision)
            guard FeedPublicationRevision.date(from: raw) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .publicationRevision, in: container, debugDescription: "Invalid publication revision")
            }
            publicationRevision = raw
        } else {
            publicationRevision = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encodeIfPresent(sourceHealth, forKey: .sourceHealth)
        try container.encodeIfPresent(contentRights, forKey: .contentRights)
        try container.encodeIfPresent(publicationRevision, forKey: .publicationRevision)
    }

    func hasValidPublicationRevision(now: Date) -> Bool {
        guard let publicationRevision else { return true }
        guard let revision = FeedPublicationRevision.date(from: publicationRevision) else { return false }
        return revision <= now.addingTimeInterval(300)
    }

    var hasValidUniqueIDs: Bool {
        var seen = Set<String>()
        for opportunity in data {
            let id = opportunity.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return false }
        }
        return true
    }

    /// Current network and bundled snapshots must prove that their upstream
    /// refresh completed. Legacy cache decoding remains possible because cache
    /// restoration does not call this remote-input validation predicate.
    var hasHealthyDeclaredSources: Bool {
        sourceHealth?.isHealthy(forPublishedCount: data.count) == true
    }

    /// Removing saved events is intentionally stricter than displaying a feed:
    /// only a publisher-declared healthy, complete snapshot may make IDs absent.
    var permitsDestructiveSavedReconciliation: Bool {
        sourceHealth?.isHealthy(forPublishedCount: data.count) == true
    }

    func hasReleaseReadyContentRights(now: Date = .now) -> Bool {
        contentRights?.isReleaseReady(for: data, feedUpdated: meta?.lastUpdated, now: now) == true
    }
}

struct OpportunityResponse: Codable {
    let data: Opportunity
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
    var includeNewFinds: Bool = true
    var volunteerHours: Bool = false
    var coop: Bool = false
    var mentorship: Bool = false
    var scholarships: Bool = false
    var blackFocused: Bool = false
    var girlsFocused: Bool = false
    var indigenousFocused: Bool = false
    var leadership: Bool = false
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
        self.includeNewFinds = filters.includeNewFinds
        self.volunteerHours = filters.volunteerHours
        self.coop = filters.coop
        self.mentorship = filters.mentorship
        self.scholarships = filters.scholarships
        self.blackFocused = filters.blackFocused
        self.girlsFocused = filters.girlsFocused
        self.indigenousFocused = filters.indigenousFocused
        self.leadership = filters.leadership
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

@Model
final class SavedOpportunityRecord {
    @Attribute(.unique) var opportunityID: String
    var payload: Data
    var savedAt: Date

    init(opportunity: Opportunity, savedAt: Date = .now) throws {
        self.opportunityID = opportunity.id
        self.payload = try JSONEncoder().encode(opportunity)
        self.savedAt = savedAt
    }

    var opportunity: Opportunity? {
        try? JSONDecoder().decode(Opportunity.self, from: payload)
    }
}

struct WatchSavedEventTransfer: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let organization: String
    let details: String
    let category: String
    let city: String
    let region: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let startDate: String?
    let endDate: String?
    let deadline: String?
    let archiveBoundary: Date?
    let archived: Bool
    let sourceURL: String?
    let registrationURL: String?
    let savedAt: Date

    init(opportunity: Opportunity, savedAt: Date, language: AppLanguage = .preferred()) {
        let summary = opportunity.localizedSummary(language: language)
        let description = opportunity.localizedDescription(language: language)
        let combinedDetails = summary == description ? summary : "\(summary)\n\n\(description)"

        id = Self.compactIdentifier(opportunity.id, limit: 200)
        title = Self.compact(opportunity.localizedTitle(language: language), limit: 140)
        organization = Self.compact(opportunity.localizedOrganization(language: language), limit: 120)
        details = Self.compact(combinedDetails, limit: 640)
        category = Self.compact(opportunity.localizedCategory(language: language), limit: 80)
        city = Self.compact(opportunity.localizedCity(language: language), limit: 80)
        region = Self.compact(opportunity.localizedRegion(language: language), limit: 80)
        address = Self.compactOptional(opportunity.localizedAddress(language: language), limit: 240)
        latitude = opportunity.latitude
        longitude = opportunity.longitude
        startDate = opportunity.startDate
        endDate = opportunity.endDate
        deadline = opportunity.deadline
        archiveBoundary = LocalOpportunitySnapshot.archiveBoundary(for: opportunity)
        archived = LocalOpportunitySnapshot.isArchived(opportunity)
        sourceURL = Self.compactOptional(opportunity.sourceUrl, limit: 500)
        registrationURL = Self.compactOptional(opportunity.registrationUrl, limit: 500)
        self.savedAt = savedAt
    }

    private static func compactOptional(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let compacted = compact(value, limit: limit)
        return compacted.isEmpty ? nil : compacted
    }

    private static func compactIdentifier(_ value: String, limit: Int) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let suffix = String(format: "%016llx", hash)
        guard !normalized.isEmpty else { return "saved-\(suffix)" }
        guard normalized.count > limit else { return normalized }
        let prefixLength = max(1, limit - suffix.count - 1)
        return "\(normalized.prefix(prefixLength))-\(suffix)"
    }

    private static func compact(_ value: String, limit: Int) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(max(0, limit - 1))).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

struct WatchSavedEventsTransfer: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let syncedAt: Date
    let totalSavedCount: Int
    let events: [WatchSavedEventTransfer]
    let preferredLanguageCode: String?

    init(
        syncedAt: Date = .now,
        totalSavedCount: Int,
        events: [WatchSavedEventTransfer],
        preferredLanguageCode: String? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.syncedAt = syncedAt
        self.totalSavedCount = totalSavedCount
        self.events = events
        self.preferredLanguageCode = preferredLanguageCode
    }
}

enum WatchSavedEventsPayloadBuilder {
    nonisolated static let maximumTransferredEvents = 48
    // updateApplicationContext serializes a surrounding property-list
    // dictionary as well as this JSON Data. Stay comfortably below the
    // transport ceiling so long localized text and URLs cannot make Watch
    // updates fail with WCError.payloadTooLarge.
    nonisolated static let maximumEncodedPayloadBytes = 48 * 1_024

    nonisolated static func makePayload(
        totalSavedCount: Int,
        prioritizedEvents: [WatchSavedEventTransfer],
        syncedAt: Date = .now,
        preferredLanguageCode: String? = nil
    ) -> Data? {
        let encoder = JSONEncoder()
        var accepted: [WatchSavedEventTransfer] = []

        for event in prioritizedEvents.prefix(maximumTransferredEvents) {
            let candidate = WatchSavedEventsTransfer(
                syncedAt: syncedAt,
                totalSavedCount: totalSavedCount,
                events: accepted + [event],
                preferredLanguageCode: preferredLanguageCode
            )
            guard let candidatePayload = try? encoder.encode(candidate) else { continue }
            guard candidatePayload.count <= maximumEncodedPayloadBytes else { continue }
            accepted.append(event)
        }

        let envelope = WatchSavedEventsTransfer(
            syncedAt: syncedAt,
            totalSavedCount: totalSavedCount,
            events: accepted,
            preferredLanguageCode: preferredLanguageCode
        )
        guard let payload = try? encoder.encode(envelope), payload.count <= maximumEncodedPayloadBytes else {
            return nil
        }
        return payload
    }
}

@MainActor
enum SavedOpportunityLibrary {
    static func isSaved(_ opportunity: Opportunity, in records: [SavedOpportunityRecord]) -> Bool {
        records.contains { $0.opportunityID == opportunity.id }
    }

    @discardableResult
    static func toggle(_ opportunity: Opportunity, in context: ModelContext) throws -> Bool {
        let opportunityID = opportunity.id
        let descriptor = FetchDescriptor<SavedOpportunityRecord>(
            predicate: #Predicate { record in record.opportunityID == opportunityID }
        )

        if let existingRecord = try context.fetch(descriptor).first {
            context.delete(existingRecord)
            try context.save()
            syncWatch(in: context)
            return false
        }

        context.insert(try SavedOpportunityRecord(opportunity: opportunity))
        try context.save()
        syncWatch(in: context)
        return true
    }

    static func deleteAll(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<SavedOpportunityRecord>()) {
            context.delete(record)
        }
        try context.save()
        syncWatch(in: context)
    }

    /// Refreshes mutable saved-event details from a retained full feed without
    /// changing when the user saved the event. Only a validated live feed may
    /// mark missing IDs unavailable; cache/bundle reconciliation updates IDs it
    /// knows about but preserves older archive snapshots that may be omitted.
    @discardableResult
    static func reconcile(
        with opportunities: [Opportunity],
        in context: ModelContext,
        markMissingAsUnavailable: Bool,
        restrictedOpportunityIDs: Set<String> = []
    ) throws -> Int {
        var latestByID = [String: Opportunity]()
        for opportunity in opportunities where !opportunity.id.isEmpty {
            latestByID[opportunity.id] = opportunity
        }

        let records = try context.fetch(FetchDescriptor<SavedOpportunityRecord>())
        var mutationCount = 0
        for record in records {
            if restrictedOpportunityIDs.contains(record.opportunityID) {
                // A rights restriction is different from an ordinary expiry:
                // remove the copied provider text instead of preserving it in
                // the local/Watch archive.
                context.delete(record)
                mutationCount += 1
                continue
            }
            let replacement: Opportunity?
            if let current = latestByID[record.opportunityID] {
                replacement = current
            } else if markMissingAsUnavailable,
                      let saved = record.opportunity,
                      saved.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "active" {
                replacement = saved.replacingStatus(with: "removed")
            } else {
                replacement = nil
            }

            guard let replacement else { continue }
            let payload = try JSONEncoder().encode(replacement)
            guard payload != record.payload else { continue }
            record.payload = payload
            mutationCount += 1
        }

        guard mutationCount > 0 else { return 0 }
        try context.save()
        syncWatch(in: context)
        return mutationCount
    }

    static func syncWatch(in context: ModelContext) {
#if os(iOS) && !targetEnvironment(macCatalyst)
        WatchSavedOpportunitySync.shared.sync(in: context)
#endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
@MainActor
final class WatchSavedOpportunitySync: NSObject, WCSessionDelegate {
    static let shared = WatchSavedOpportunitySync()

    nonisolated static let payloadKey = "savedEventsPayload"
    nonisolated static let requestKey = "requestSavedEvents"
    nonisolated static let preferredLanguageKey = "preferredLanguageCode"

    private var modelContainer: ModelContainer?
    private var latestPayload: Data?
    private var preferredLanguageCode = AppLanguage.preferred().rawValue
    private(set) var lastPublishErrorDescription: String?
    private var isConfigured = false

    private override init() {
        super.init()
    }

    func configure(container: ModelContainer) {
        modelContainer = container
        preferredLanguageCode = AppLanguage.preferred().rawValue
        activateIfSupported()
        syncLatest()
    }

    func preferredLanguageDidChange(to code: String) {
        preferredLanguageCode = AppLanguage.normalized(code).rawValue
        if modelContainer != nil {
            syncLatest()
        } else {
            publishLatestPayload()
        }
    }

    func sync(in context: ModelContext) {
        // Never publish from an unconfigured (including emergency in-memory)
        // container. An empty recovery store must not replace the Watch's last
        // known-good saved-event cache.
        guard isConfigured else { return }
        let descriptor = FetchDescriptor<SavedOpportunityRecord>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return }

        let language = AppLanguage.normalized(preferredLanguageCode)
        let decoded = records.compactMap { record -> (event: WatchSavedEventTransfer, archived: Bool)? in
            guard let opportunity = record.opportunity else { return nil }
            return (
                WatchSavedEventTransfer(opportunity: opportunity, savedAt: record.savedAt, language: language),
                LocalOpportunitySnapshot.isArchived(opportunity)
            )
        }
        let prioritized = decoded.filter { !$0.archived } + decoded.filter(\.archived)
        guard let payload = WatchSavedEventsPayloadBuilder.makePayload(
            totalSavedCount: decoded.count,
            prioritizedEvents: prioritized.map(\.event),
            preferredLanguageCode: language.rawValue
        ) else { return }

        latestPayload = payload
        publishLatestPayload()
    }

    private func activateIfSupported() {
        guard WCSession.isSupported(), !isConfigured else { return }
        isConfigured = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func syncLatest() {
        guard let modelContainer else { return }
        sync(in: ModelContext(modelContainer))
    }

    private func publishLatestPayload() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }
        do {
            var context: [String: Any] = [
                Self.preferredLanguageKey: preferredLanguageCode
            ]
            if let latestPayload {
                context[Self.payloadKey] = latestPayload
            }
            try session.updateApplicationContext(context)
            lastPublishErrorDescription = nil
        } catch {
            lastPublishErrorDescription = error.localizedDescription
            NSLog("GTA FREE STEM Watch sync failed: %@", error.localizedDescription)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor [weak self] in
            self?.syncLatest()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isConfigured = false
            self?.activateIfSupported()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.syncLatest()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[Self.requestKey] as? Bool == true else { return }
        Task { @MainActor [weak self] in
            self?.syncLatest()
        }
    }
}
#endif

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
    var volunteerHours = false
    var coop = false
    var mentorship = false
    var scholarships = false
    var blackFocused = false
    var girlsFocused = false
    var indigenousFocused = false
    var leadership = false

    var hasLocation: Bool {
        OpportunityCoordinate.isValid(latitude: latitude, longitude: longitude)
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
            volunteerHours ||
            coop ||
            mentorship ||
            scholarships ||
            blackFocused ||
            girlsFocused ||
            indigenousFocused ||
            leadership
    }
}

struct OpportunityMapVenue: Identifiable, Sendable {
    let id: String
    let address: String
    let latitude: Double
    let longitude: Double
    let opportunities: [Opportunity]
}

struct OpportunityMapViewport: Sendable {
    let latitude: Double
    let longitude: Double
    let distance: Double
    let pitch: Double
}

struct OpportunityMapSnapshot: Sendable {
    let venues: [OpportunityMapVenue]
    let mappedCount: Int
    let viewport: OpportunityMapViewport?

    static let empty = OpportunityMapSnapshot(venues: [], mappedCount: 0, viewport: nil)
}

enum OpportunityMapProjection {
    static func snapshot(from opportunities: [Opportunity]) -> OpportunityMapSnapshot {
        let venues = venues(from: opportunities)
        return OpportunityMapSnapshot(venues: venues,
                                      mappedCount: venues.reduce(0) { $0 + $1.opportunities.count },
                                      viewport: viewport(for: venues))
    }

    static func pins(from opportunities: [Opportunity]) -> [Opportunity] {
        opportunities.filter { opportunity in
            let address = normalizedAddress(opportunity.address)
            // An online listing may carry a city-centre fallback coordinate.
            // A missing physical address must remain list-only, too.
            return !opportunity.virtual && !address.isEmpty && !address.hasPrefix("online") && !address.hasPrefix("virtual") &&
                OpportunityCoordinate.isValid(latitude: opportunity.latitude, longitude: opportunity.longitude)
        }
    }

    static func venues(from opportunities: [Opportunity]) -> [OpportunityMapVenue] {
        let mapped = pins(from: opportunities)
        var order: [String] = []
        var groups: [String: [Opportunity]] = [:]
        for opportunity in mapped {
            guard !Task.isCancelled else { return [] }
            // The address AND source coordinate must agree. Distinct venues
            // sharing a municipal fallback coordinate must never be merged.
            let key = "\(normalizedAddress(opportunity.address))|\(opportunity.latitude!)|\(opportunity.longitude!)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(opportunity)
        }
        return order.compactMap { key in
            guard let records = groups[key], let first = records.first,
                  let latitude = first.latitude, let longitude = first.longitude else { return nil }
            return OpportunityMapVenue(id: key, address: (first.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                       latitude: latitude, longitude: longitude, opportunities: records)
        }
    }

    static func viewport(for venues: [OpportunityMapVenue]) -> OpportunityMapViewport? {
        guard let first = venues.first else { return nil }
        let latitudes = venues.map(\.latitude)
        let longitudes = venues.map(\.longitude)
        let latitude = ((latitudes.min() ?? first.latitude) + (latitudes.max() ?? first.latitude)) / 2
        let longitude = ((longitudes.min() ?? first.longitude) + (longitudes.max() ?? first.longitude)) / 2
        let northSouth = ((latitudes.max() ?? latitude) - (latitudes.min() ?? latitude)) * 111_320
        let eastWest = ((longitudes.max() ?? longitude) - (longitudes.min() ?? longitude)) * 111_320 * cos(latitude * .pi / 180)
        let distance = max(2_400, hypot(northSouth, eastWest) * 2.2)
        return OpportunityMapViewport(latitude: latitude, longitude: longitude, distance: distance,
                                      pitch: distance <= 20_000 ? 55 : 35)
    }

    private static func normalizedAddress(_ address: String?) -> String {
        (address ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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
