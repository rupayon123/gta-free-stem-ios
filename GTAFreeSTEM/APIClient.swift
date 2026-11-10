import Foundation
import CryptoKit
import NaturalLanguage

/// Sentence chunks preserve every source byte; this does not assert semantic
/// translation quality. The entire field is published only after all parts pass.
enum ListingTranslationSegmentation {
    static func split(_ text: String, maxBytes: Int = 512, maxSegments: Int = 256) -> [String]? {
        guard maxBytes > 0, maxSegments > 0, !text.isEmpty else { return nil }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var boundaries: [String.Index] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            boundaries.append(range.upperBound)
            return true
        }
        if boundaries.last != text.endIndex { boundaries.append(text.endIndex) }
        var cursor = text.startIndex
        var output: [String] = []
        for boundary in boundaries where boundary > cursor {
            var start = cursor
            while start < boundary {
                var position = start, bytes = 0
                var safeBreak: String.Index?
                while position < boundary {
                    let next = text.index(after: position)
                    let character = text[position]
                    let count = text[position..<next].utf8.count
                    if bytes + count > maxBytes { break }
                    bytes += count
                    if character.isWhitespace { safeBreak = next }
                    position = next
                }
                if position < boundary {
                    // Never cut a provider's word, URL, or composed character.
                    guard let safeBreak, safeBreak > start else { return nil }
                    position = safeBreak
                }
                output.append(String(text[start..<position]))
                guard output.count <= maxSegments else { return nil }
                start = position
            }
            guard output.count <= maxSegments else { return nil }
            cursor = boundary
        }
        guard !output.isEmpty, output.joined().utf8.elementsEqual(text.utf8) else { return nil }
        return output
    }
}

struct ListingTranslationPlan: Sendable {
    struct Part: Sendable {
        let fieldIndex: Int
        let ordinal: Int
        let source: String
        var id: String { "\(fieldIndex):\(ordinal)" }
        var needsTranslation: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    struct Result: Sendable {
        let id: String
        let source: String
        let target: String
    }
    let fields: [[Part]]
    var requests: [Part] { fields.flatMap { $0 }.filter(\.needsTranslation) }

    static func make(_ inputs: [ListingTranslationInput], maxRequests: Int = 64, maxBytes: Int = 100_000) -> Self? {
        var fields: [[Part]] = [], count = 0, bytes = 0
        for (index, input) in inputs.enumerated() {
            let chunks: [String]
            if input.field == "description" && input.source.utf8.count > 512 {
                guard let split = ListingTranslationSegmentation.split(input.source) else { return nil }
                chunks = split
            } else { chunks = [input.source] }
            guard chunks.joined().utf8.elementsEqual(input.source.utf8) else { return nil }
            let parts = chunks.enumerated().map { Part(fieldIndex: index, ordinal: $0.offset, source: $0.element) }
            count += parts.filter(\.needsTranslation).count
            bytes += input.source.utf8.count
            guard count <= maxRequests, bytes <= maxBytes else { return nil }
            fields.append(parts)
        }
        return Self(fields: fields)
    }

    func assemble(_ results: [Result]) -> [String: String] {
        var byID: [String: Result] = [:]
        var duplicates = Set<String>()
        for result in results {
            if byID.updateValue(result, forKey: result.id) != nil { duplicates.insert(result.id) }
        }
        var output: [String: String] = [:]
        for (index, parts) in fields.enumerated() {
            var translated = "", valid = true
            for part in parts {
                guard part.needsTranslation else { translated += part.source; continue }
                guard !duplicates.contains(part.id), let result = byID[part.id],
                      result.source.utf8.elementsEqual(part.source.utf8),
                      !result.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { valid = false; break }
                let leading = String(part.source.prefix(while: { $0.isWhitespace }))
                let trailing = String(part.source.reversed().prefix(while: { $0.isWhitespace }).reversed())
                translated += leading + result.target.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
            }
            if valid && translated.utf8.count <= 600_000 { output[String(index)] = translated }
        }
        return output
    }
}

/// Field-level binding for a translation pack after its manifest, source index,
/// provenance and bytes have been independently validated. This does not fetch
/// or enable a catalog: a qualified public endpoint does not yet exist.
enum FullDescriptionBinding {
    struct SourceRecord {
        let id: String
        let organization: String
        let sourceURL: String
        let titleSHA256: String
        let descriptionSHA256: String
    }

    struct Entry {
        let text: String
        let sourceSegmentCount: Int
        let translatedSegmentCount: Int
        let endedNormally: Bool
    }

    struct Result {
        let title: String?
        let description: String?
    }

    static func hash(_ text: String) -> String {
        hashBytes(Data(text.utf8))
    }

    static func hashBytes(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func resolve(
        id: String, organization: String, sourceURL: String,
        title: String, description: String,
        requestedLanguage: AppLanguage, packLanguage: String,
        record: SourceRecord, entries: [String: Entry]
    ) -> Result? {
        // Compare identity bytes as well as the actual field hashes. Swift's
        // normal String equality permits Unicode canonical equivalence.
        func sameBytes(_ left: String, _ right: String) -> Bool {
            left.utf8.elementsEqual(right.utf8)
        }
        guard requestedLanguage != .en,
              sameBytes(requestedLanguage.rawValue, packLanguage),
              sameBytes(id, record.id), sameBytes(organization, record.organization),
              sameBytes(sourceURL, record.sourceURL) else { return nil }

        func boundText(_ original: String, _ expectedHash: String) -> String? {
            guard hash(original) == expectedHash, let entry = entries[expectedHash],
                  entry.sourceSegmentCount > 0,
                  entry.sourceSegmentCount == entry.translatedSegmentCount,
                  entry.endedNormally,
                  !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.text.utf8.count <= 600_000 else { return nil }
            return entry.text
        }
        return Result(title: boundText(title, record.titleSHA256),
                      description: boundText(description, record.descriptionSHA256))
    }
}

/// An immutable, source-bound overlay. The caller must obtain the expected
/// digest from an independently approved, authenticated publication; a digest
/// supplied by the downloaded pack itself is not authority. No transport or
/// production endpoint is enabled by this type.
struct PreparedListingOverlay: Sendable {
    enum ValidationError: Error { case invalid }
    private struct SourceFeed: Decodable { let count: Int; let opportunities: [Opportunity] }
    private struct Pack: Decodable {
        struct SourceIndex: Decodable {
            struct Record: Decodable {
                let id: String
                let provider: String
                let sourceURL: String
                let titleSHA256: String
                let descriptionSHA256: String
            }
            let sourceFeedSHA256: String
            let records: [Record]
        }
        struct Entry: Decodable {
            struct Segment: Decodable {
                let ordinal: Int
                let source: String
                let target: String
                let targetSHA256: String
                let endedNormally: Bool
                let kind: String?
                private enum CodingKeys: String, CodingKey {
                    case ordinal, source, target, targetSHA256, endedNormally, kind, sourceTokenID, targetTokenID, responseLocale
                }
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    ordinal = try container.decode(Int.self, forKey: .ordinal)
                    source = try container.decode(String.self, forKey: .source)
                    target = try container.decode(String.self, forKey: .target)
                    targetSHA256 = try container.decode(String.self, forKey: .targetSHA256)
                    endedNormally = try container.decode(Bool.self, forKey: .endedNormally)
                    kind = try container.decodeIfPresent(String.self, forKey: .kind)
                    if kind == "verbatim-identifier" {
                        for key in [CodingKeys.sourceTokenID, .targetTokenID, .responseLocale] {
                            guard container.contains(key), try container.decodeNil(forKey: key) else { throw ValidationError.invalid }
                        }
                    }
                }
            }
            let segments: [Segment]
        }
        let schemaVersion: Int
        let locale: String
        let generatedAt: String
        let expiresAt: String
        let sourceIndex: SourceIndex
        let entryCount: Int
        let entries: [String: Entry]
    }

    private struct BoundRecord: Sendable {
        let id: String
        let provider: String
        let sourceURL: String
        let titleHash: String
        let bodyHash: String
    }
    private let records: [String: BoundRecord]
    private let translatedFields: [String: String]
    let locale: AppLanguage
    let packSHA256: String
    let sourceFeedSHA256: String
    let generatedAt: Date
    let expiresAt: Date

    static func validateOffMain(data: Data, sourceFeedData: Data, locale: AppLanguage,
                                expectedPackSHA256: String, now: Date = .now) async throws -> Self {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try Self.validate(data: data, sourceFeedData: sourceFeedData, locale: locale,
                                     expectedPackSHA256: expectedPackSHA256, now: now)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    static func validate(data: Data, sourceFeedData: Data, locale: AppLanguage,
                         expectedPackSHA256: String, now: Date = .now) throws -> Self {
        guard locale != .en, data.count <= 8_000_000, sourceFeedData.count <= 10_000_000,
              FullDescriptionBinding.hashBytes(data) == expectedPackSHA256 else { throw ValidationError.invalid }
        let pack = try JSONDecoder().decode(Pack.self, from: data)
        let feed = try JSONDecoder().decode(SourceFeed.self, from: sourceFeedData)
        let opportunities = feed.opportunities
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        func parse(_ value: String) -> Date? { dates.date(from: value) ?? plainDates.date(from: value) }
        guard pack.schemaVersion == 1, pack.locale == locale.rawValue,
              let generated = parse(pack.generatedAt), let expires = parse(pack.expiresAt),
              generated <= now, now < expires, expires.timeIntervalSince(generated) <= 30 * 24 * 60 * 60,
              pack.sourceIndex.sourceFeedSHA256 == FullDescriptionBinding.hashBytes(sourceFeedData),
              feed.count == opportunities.count, pack.sourceIndex.records.count == opportunities.count, opportunities.count <= 4_999,
              pack.entryCount == pack.entries.count else { throw ValidationError.invalid }
        var expected: [String: Opportunity] = [:]
        for item in opportunities {
            let key = FullDescriptionBinding.hash(item.id)
            guard expected.updateValue(item, forKey: key) == nil else { throw ValidationError.invalid }
        }
        var records: [String: BoundRecord] = [:]
        var requiredSources: [String: String] = [:]
        for record in pack.sourceIndex.records {
            try Task.checkCancellation()
            let idHash = FullDescriptionBinding.hash(record.id)
            guard let opportunity = expected[idHash], records[idHash] == nil,
                  opportunity.id.utf8.elementsEqual(record.id.utf8),
                  opportunity.organization.utf8.elementsEqual(record.provider.utf8),
                  opportunity.sourceUrl.utf8.elementsEqual(record.sourceURL.utf8),
                  FullDescriptionBinding.hash(opportunity.title) == record.titleSHA256,
                  FullDescriptionBinding.hash(opportunity.description) == record.descriptionSHA256 else { throw ValidationError.invalid }
            records[idHash] = BoundRecord(id: record.id, provider: record.provider, sourceURL: record.sourceURL,
                                          titleHash: record.titleSHA256, bodyHash: record.descriptionSHA256)
            for (hash, source) in [(record.titleSHA256, opportunity.title), (record.descriptionSHA256, opportunity.description)] {
                if let previous = requiredSources[hash], !previous.utf8.elementsEqual(source.utf8) { throw ValidationError.invalid }
                requiredSources[hash] = source
            }
        }
        guard Set(pack.entries.keys) == Set(requiredSources.keys) else { throw ValidationError.invalid }
        var fields: [String: String] = [:]
        for (hash, source) in requiredSources {
            try Task.checkCancellation()
            guard let entry = pack.entries[hash], !entry.segments.isEmpty, entry.segments.count <= 256 else { throw ValidationError.invalid }
            var assembledSource = "", assembledTarget = ""
            for (index, segment) in entry.segments.enumerated() {
                try Task.checkCancellation()
                guard segment.ordinal == index, !segment.source.isEmpty,
                      !segment.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      FullDescriptionBinding.hash(segment.target) == segment.targetSHA256 else { throw ValidationError.invalid }
                switch segment.kind ?? "model-translation" {
                case "model-translation":
                    guard segment.endedNormally else { throw ValidationError.invalid }
                case "verbatim-identifier":
                    let allowed = Set(["AI", "API", "CSS", "HTML", "SQL", "STEAM", "STEM"])
                    guard !segment.endedNormally, segment.source.utf8.count <= 128,
                          segment.source.utf8.elementsEqual(segment.target.utf8), allowed.contains(segment.source.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ValidationError.invalid }
                default: throw ValidationError.invalid
                }
                assembledSource += segment.source
                assembledTarget += segment.target
                guard assembledSource.utf8.count <= 600_000, assembledTarget.utf8.count <= 600_000 else { throw ValidationError.invalid }
            }
            guard assembledSource.utf8.elementsEqual(source.utf8) else { throw ValidationError.invalid }
            fields[hash] = assembledTarget
        }
        return Self(records: records, translatedFields: fields, locale: locale, packSHA256: expectedPackSHA256,
                    sourceFeedSHA256: pack.sourceIndex.sourceFeedSHA256, generatedAt: generated, expiresAt: expires)
    }

    func resolve(_ opportunity: Opportunity, now: Date = .now) -> (title: String, description: String)? {
        guard now >= generatedAt, now < expiresAt,
              let record = records[FullDescriptionBinding.hash(opportunity.id)],
              record.id.utf8.elementsEqual(opportunity.id.utf8),
              record.provider.utf8.elementsEqual(opportunity.organization.utf8),
              record.sourceURL.utf8.elementsEqual(opportunity.sourceUrl.utf8),
              record.titleHash == FullDescriptionBinding.hash(opportunity.title),
              record.bodyHash == FullDescriptionBinding.hash(opportunity.description),
              let title = translatedFields[record.titleHash], let body = translatedFields[record.bodyHash] else { return nil }
        return (title, body)
    }
}

/// Signed-app translations for reviewed public youth fields and repeated provider notes.
/// A source hash, field namespace and (for youth) record identity must all match.
struct SourceBoundSmallTranslations: Sendable {
    private struct BundleData: Decodable {
        struct Youth: Decodable { let id: String; let field: String; let sourceSHA256: String; let translations: [String: String] }
        struct Supplemental: Decodable { let sourceSHA256: String; let translations: [String: String] }
        let schemaVersion: Int
        let youth: [Youth]
        let supplemental: [Supplemental]
    }
    private let youth: [String: [String: String]]
    private let supplemental: [String: [String: String]]
    private static let separator = "\u{1f}"
    private static func youthKey(_ id: String, _ field: String, _ hash: String) -> String { id + separator + field + separator + hash }
    private static func numbered(_ field: String, prefix: String, parts: Int = 1) -> Bool {
        guard field.hasPrefix(prefix) else { return false }
        let numbers = field.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)
        return numbers.count == parts && numbers.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
    }
    private static func validYouthField(_ field: String) -> Bool {
        ["title", "audience", "residency", "cost", "availability", "commitment", "hours"].contains(field) ||
            numbered(field, prefix: "restriction-") || numbered(field, prefix: "required-cost-")
    }
    static func decode(_ data: Data, expectedSHA256: String) -> Self? {
        guard data.count <= 500_000, FullDescriptionBinding.hashBytes(data) == expectedSHA256,
              let input = try? JSONDecoder().decode(BundleData.self, from: data), input.schemaVersion == 1,
              input.youth.count <= 500, input.supplemental.count <= 100 else { return nil }
        let languages = Set(AppLanguage.allCases.map(\.rawValue))
        func valid(_ hash: String, _ translations: [String: String]) -> Bool {
            hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
                Set(translations.keys) == languages && translations.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        var youth: [String: [String: String]] = [:], supplemental: [String: [String: String]] = [:]
        for item in input.youth {
            guard !item.id.isEmpty, !item.id.contains(separator), validYouthField(item.field), valid(item.sourceSHA256, item.translations),
                  youth.updateValue(item.translations, forKey: youthKey(item.id, item.field, item.sourceSHA256)) == nil else { return nil }
        }
        for item in input.supplemental {
            guard valid(item.sourceSHA256, item.translations), supplemental.updateValue(item.translations, forKey: item.sourceSHA256) == nil else { return nil }
        }
        return Self(youth: youth, supplemental: supplemental)
    }
    func resolve(_ input: ListingTranslationInput, language: AppLanguage) -> String? {
        guard language != .en else { return nil }
        let sourceHash = FullDescriptionBinding.hash(input.source)
        if input.listingID.hasPrefix("youth:") {
            guard Self.validYouthField(input.field) else { return nil }
            let id = String(input.listingID.dropFirst("youth:".count))
            return youth[Self.youthKey(id, input.field, sourceHash)]?[language.rawValue]
        }
        guard Self.numbered(input.field, prefix: "note-") || Self.numbered(input.field, prefix: "evidence-") ||
              Self.numbered(input.field, prefix: "condition-", parts: 2) else { return nil }
        return supplemental[sourceHash]?[language.rawValue]
    }
}

/// A small, process-only cache; the exact source bytes and target language are
/// part of the key so an updated listing cannot reuse an older translation.
struct ListingTranslationKey: Hashable {
    let listingHash: String
    let sourceHash: String
    let contextHash: String
    let targetLocale: String
    let field: String

    init(listingID: String, source: String, targetLocale: String, field: String = "description", sourceHint: String? = nil) {
        listingHash = FullDescriptionBinding.hash(listingID)
        sourceHash = FullDescriptionBinding.hash(source)
        contextHash = FullDescriptionBinding.hash(sourceHint ?? source)
        self.targetLocale = targetLocale
        self.field = field
    }

    init(listingHash: String, sourceHash: String, contextHash: String, targetLocale: String, field: String) {
        self.listingHash = listingHash
        self.sourceHash = sourceHash
        self.contextHash = contextHash
        self.targetLocale = targetLocale
        self.field = field
    }
}

/// Actual provider text, never a generated browsing summary. The hint is used
/// only to identify the language of short titles and proper names.
struct ListingTranslationInput: Hashable, Sendable {
    let listingID: String
    let field: String
    let source: String
    let sourceHint: String?
    private let listingHash: String
    private let sourceHash: String
    private let contextHash: String

    init(listingID: String, field: String, source: String, sourceHint: String? = nil) {
        self.listingID = listingID
        self.field = field
        self.source = source
        self.sourceHint = sourceHint
        listingHash = FullDescriptionBinding.hash(listingID)
        sourceHash = FullDescriptionBinding.hash(source)
        contextHash = FullDescriptionBinding.hash(sourceHint ?? source)
    }

    func key(target: String) -> ListingTranslationKey {
        ListingTranslationKey(listingHash: listingHash, sourceHash: sourceHash, contextHash: contextHash, targetLocale: target, field: field)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.listingID.utf8.elementsEqual(rhs.listingID.utf8) && lhs.field.utf8.elementsEqual(rhs.field.utf8) &&
        lhs.source.utf8.elementsEqual(rhs.source.utf8) &&
        (lhs.sourceHint ?? lhs.source).utf8.elementsEqual((rhs.sourceHint ?? rhs.source).utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Data(listingID.utf8)); hasher.combine(Data(field.utf8))
        hasher.combine(Data(source.utf8)); hasher.combine(Data((sourceHint ?? source).utf8))
    }
}

enum ListingTranslationState: Equatable, Sendable {
    case original, waiting, translated, unavailable, failed
}

struct ListingTranslationBatch: Sendable {
    let id: UUID
    let target: String
    let sourceLanguage: String
    let inputs: [ListingTranslationInput]
}

@MainActor
final class ListingTranslationCache {
    static let shared = ListingTranslationCache()
    private var entries: [ListingTranslationKey: String] = [:]
    private var order: [ListingTranslationKey] = []
    private let limit: Int
    private let byteLimit: Int

    init(limit: Int = 20, byteLimit: Int = 600_000) {
        self.limit = max(0, limit)
        self.byteLimit = max(0, byteLimit)
    }

    func value(for key: ListingTranslationKey) -> String? { entries[key] }

    func insert(_ value: String, for key: ListingTranslationKey) {
        guard limit > 0, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= byteLimit else { return }
        entries[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > limit || entries.values.reduce(0, { $0 + $1.utf8.count }) > byteLimit {
            entries.removeValue(forKey: order.removeFirst())
        }
    }
}

enum APIError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case insecureConnection

    var errorDescription: String? {
        switch self {
        case .badURL: Self.localized("serverAddressInvalid")
        case .invalidResponse: Self.localized("serverResponseInvalid")
        case .insecureConnection: Self.localized("serverAddressInvalid")
        }
    }

    private static func localized(_ key: String) -> String {
        let language = AppLanguage.preferred()
        return AppText.shared.string(key, language: language)
    }
}

final class APIClient: @unchecked Sendable {
    static let primaryPublicFeedURL = URL(string: "https://raw.githubusercontent.com/rupayon123/gta-free-stem-opportunities/main/public/opportunities-v2.json")!
    // A CDN mirror keeps a current, independent retrieval path when the raw
    // GitHub endpoint is temporarily unavailable. Every source is still held
    // to the same HTTPS, payload-size, schema, and freshness checks below.
    static let fallbackPublicFeedURL = URL(string: "https://cdn.jsdelivr.net/gh/rupayon123/gta-free-stem-opportunities@main/public/opportunities-v2.json")!

    let feedURL: URL
    private let fallbackFeedURLs: [URL]
    private let session: URLSession
    private let now: () -> Date
    private static let maxResponseBytes = 10_000_000
    private static let bundledTranslationIndex: [String: Opportunity] = {
        guard let url = AppResources.url(forResource: "opportunities", withExtension: "json") else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        guard let response = try? JSONDecoder().decode(OpportunityListResponse.self, from: data) else {
            return [:]
        }

        var index: [String: Opportunity] = [:]
        for opportunity in response.data where !opportunity.id.isEmpty {
            guard !opportunity.translations.isEmpty else { continue }
            index[opportunity.id] = opportunity
        }

        return index
    }()

    init(
        feedURL: URL? = nil,
        fallbackFeedURLs: [URL]? = nil,
        session: URLSession? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        let primaryFeedURL = feedURL ?? Self.primaryPublicFeedURL
        self.feedURL = primaryFeedURL
        self.fallbackFeedURLs = (fallbackFeedURLs ?? (feedURL == nil ? [Self.fallbackPublicFeedURL] : []))
            .filter { $0 != primaryFeedURL }
        self.session = session ?? Self.defaultSession
        self.now = now
    }

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        // The app has a retained local snapshot, so an offline device should
        // surface that usable state immediately instead of holding a refresh
        // request open while the system waits for a network path.
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func opportunities(query: String, mode: SearchMode, filters: OpportunityFilters) async throws -> OpportunityListResponse {
        let response = try await opportunityFeed()
        let filtered = LocalOpportunitySnapshot.filter(
            response.data,
            query: query,
            mode: mode,
            filters: filters,
            now: now()
        )
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(
                activeCount: filtered.count,
                lastUpdated: response.meta?.lastUpdated
            ),
            publicationRevision: response.publicationRevision
        )
    }

    func opportunityFeed() async throws -> OpportunityListResponse {
        var lastError: Error?

        for source in [feedURL] + fallbackFeedURLs {
            try Task.checkCancellation()
            do {
                let (response, originalBytes): (OpportunityListResponse, Data) = try await get(source)
                try Task.checkCancellation()
                guard FeedFreshness.isCurrent(response.meta?.lastUpdated, now: now()) else {
                    throw APIError.invalidResponse
                }
                // An empty yet recent response is not useful to this discovery
                // app and is most often a partial publisher failure. Retain the
                // last good cache or bundled fallback instead of replacing it.
                guard !response.data.isEmpty else {
                    throw APIError.invalidResponse
                }
                guard response.hasValidUniqueIDs, response.hasHealthyDeclaredSources,
                      response.hasValidPublicationRevision(now: now()) else {
                    throw APIError.invalidResponse
                }
                guard response.hasReleaseReadyContentRights(now: now()) else {
                    throw APIError.invalidResponse
                }
                return Self.applyBundledTranslations(from: response, sourceFeedBytes: originalBytes)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    static func applyBundledTranslations(from response: OpportunityListResponse, sourceFeedBytes: Data) -> OpportunityListResponse {
        let mergedData = response.data.map { augment(withBundledTranslations: $0) }
        return OpportunityListResponse(
            data: mergedData,
            meta: response.meta,
            sourceHealth: response.sourceHealth,
            contentRights: response.contentRights,
            publicationRevision: response.publicationRevision,
            sourceFeedBytes: sourceFeedBytes
        )
    }

    private static func augment(withBundledTranslations opportunity: Opportunity) -> Opportunity {
        guard let bundled = Self.bundledTranslationIndex[opportunity.id], Self.sameBundledSource(bundled, opportunity) else {
            return opportunity
        }
        return Self.mergingBundledTranslations(bundled.translations, into: opportunity)
    }

    static func sameBundledSource(_ bundled: Opportunity, _ current: Opportunity) -> Bool {
        bundled.id.utf8.elementsEqual(current.id.utf8) && bundled.organization.utf8.elementsEqual(current.organization.utf8) &&
        bundled.sourceUrl.utf8.elementsEqual(current.sourceUrl.utf8) && bundled.title.utf8.elementsEqual(current.title.utf8) &&
        bundled.description.utf8.elementsEqual(current.description.utf8)
    }

    static func mergingBundledTranslations(_ bundled: [String: OpportunityTranslation], into opportunity: Opportunity) -> Opportunity {
        var translations = bundled
        for (key, remoteTranslation) in opportunity.translations {
            let supportedLanguage = AppLanguage.supportedLanguage(for: key)
            let fallback = bundled[key] ?? supportedLanguage.flatMap { bundled[$0.rawValue] }
            translations[key] = remoteTranslation.merged(with: fallback)
            if let supportedLanguage {
                translations[supportedLanguage.rawValue] = translations[key]
            }
        }
        let mergedTranslations = translations.compactMapValues { $0.hasContent ? $0 : nil }
        return Opportunity(
            id: opportunity.id,
            title: opportunity.title,
            organization: opportunity.organization,
            description: opportunity.description,
            summary: opportunity.summary,
            category: opportunity.category,
            city: opportunity.city,
            region: opportunity.region,
            address: opportunity.address,
            latitude: opportunity.latitude,
            longitude: opportunity.longitude,
            startDate: opportunity.startDate,
            endDate: opportunity.endDate,
            deadline: opportunity.deadline,
            ageMin: opportunity.ageMin,
            ageMax: opportunity.ageMax,
            language: opportunity.language,
            cost: opportunity.cost,
            sourceUrl: opportunity.sourceUrl,
            registrationUrl: opportunity.registrationUrl,
            status: opportunity.status,
            volunteerHoursEligible: opportunity.volunteerHoursEligible,
            coopEligible: opportunity.coopEligible,
            tags: opportunity.tags,
            distanceKm: opportunity.distanceKm,
            isNewFind: opportunity.isNewFind,
            sourceConfidence: opportunity.sourceConfidence,
            translations: mergedTranslations,
            virtual: opportunity.virtual,
            accessibility: opportunity.accessibility,
            accessibilitySupport: opportunity.accessibilitySupport,
            accessibilitySupportUnavailable: opportunity.accessibilitySupportUnavailable
        )
    }

    private func get<T: Decodable>(_ url: URL) async throws -> (T, Data) {
        try Task.checkCancellation()
        guard Self.isTrustedTransport(url) else { throw APIError.insecureConnection }
        let (bytes, response) = try await session.bytes(from: url)
        let responseTask = bytes.task
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw APIError.invalidResponse
                }
                guard let finalURL = http.url, Self.isTrustedTransport(finalURL) else {
                    throw APIError.insecureConnection
                }
                guard response.expectedContentLength <= Int64(Self.maxResponseBytes) else {
                    throw APIError.invalidResponse
                }

                var data = Data()
                if response.expectedContentLength > 0 {
                    data.reserveCapacity(Int(response.expectedContentLength))
                }
                for try await byte in bytes {
                    // Unknown or understated lengths still cannot grow the
                    // retained payload beyond the cap while the body arrives.
                    guard data.count < Self.maxResponseBytes else { throw APIError.invalidResponse }
                    data.append(byte)
                    if data.count.isMultiple(of: 65_536) {
                        try Task.checkCancellation()
                    }
                }
                try Task.checkCancellation()
                return (try JSONDecoder().decode(T.self, from: data), data)
            } onCancel: {
                responseTask.cancel()
            }
        } catch {
            // Header rejection and byte overflow must stop the transfer, not
            // leave a response downloading after the caller moves to a mirror.
            responseTask.cancel()
            throw error
        }
    }

    private static func isTrustedTransport(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.host?.isEmpty == false
    }

}
