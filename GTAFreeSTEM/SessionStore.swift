import SwiftUI
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

@MainActor
final class SessionStore: ObservableObject {
    @Published var displayName = AppText.shared.string("guest", language: .en)
    @Published var preferredLanguageCode: String {
        didSet {
            let normalized = AppLanguage.normalized(preferredLanguageCode).rawValue
            if preferredLanguageCode != normalized {
                preferredLanguageCode = normalized
                return
            }
            defaults.set(normalized, forKey: AppLanguage.preferredLanguageDefaultsKey)
            translationLanguageChanged()
#if os(iOS) && !targetEnvironment(macCatalyst)
            WatchSavedOpportunitySync.shared.preferredLanguageDidChange(to: normalized)
#endif
            if !hasLocalProfile {
                displayName = AppText.shared.string("guest", language: AppLanguage.normalized(normalized))
            }
        }
    }
    @Published var preferredTheme: String {
        didSet {
            if !["System", "Light", "Dark"].contains(preferredTheme) {
                preferredTheme = "System"
            }
            defaults.set(preferredTheme, forKey: Self.themeKey)
        }
    }

    private static let themeKey = "preferredTheme"
    private static let localProfileNameKey = "localProfileName"
    private static let localProfileEnabledKey = "localProfileEnabled"
    private let defaults: UserDefaults
    @Published private(set) var translationWorkRevision = 0
    @Published private(set) var translationRevision = 0
    private struct TranslationDemand {
        let inputs: [ListingTranslationInput]
        let priority: Int
        let order: Int
    }
    private var translationDemands: [UUID: TranslationDemand] = [:]
    private var translationDemandOrder = 0
    private var translationValues: [ListingTranslationKey: String] = [:]
    private var translationStates: [ListingTranslationKey: ListingTranslationState] = [:]
    private var translationResultOrder: [ListingTranslationKey] = []
    private var activeTranslationBatch: UUID?
    private enum SourceDetection: Sendable { case language(String), unavailable }
    private var sourceDetectionCache: [ListingTranslationKey: SourceDetection] = [:]
    private var sourceDetectionOrder: [ListingTranslationKey] = []
    private var smallSourceBundle: SourceBoundSmallTranslations?
    private var smallSourceBundleLoaded = false
    private var smallSourceBundleTask: Task<SourceBoundSmallTranslations?, Never>?

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        let initialLanguage = AppLanguage.preferred(defaults: defaults, preferredLanguages: preferredLanguages)
        preferredLanguageCode = initialLanguage.rawValue
        preferredTheme = defaults.string(forKey: Self.themeKey) ?? "Light"
        defaults.set(initialLanguage.rawValue, forKey: AppLanguage.preferredLanguageDefaultsKey)
        if defaults.bool(forKey: Self.localProfileEnabledKey),
           let savedName = defaults.string(forKey: Self.localProfileNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !savedName.isEmpty {
            displayName = savedName
        } else {
            displayName = text("guest")
        }
    }

    var hasLocalProfile: Bool {
        defaults.bool(forKey: Self.localProfileEnabledKey)
    }

    var language: AppLanguage {
        AppLanguage.normalized(preferredLanguageCode)
    }

    var colorScheme: ColorScheme? {
        switch preferredTheme {
        case "Light": .light
        case "Dark": .dark
        default: nil
        }
    }

    func text(_ key: String) -> String {
        AppText.shared.string(key, language: language)
    }

    func languageName(_ language: AppLanguage) -> String {
        AppText.shared.languageName(language)
    }

    func title(for opportunity: Opportunity) -> String {
        let text = opportunity.localizedTitle(language: language)
        return text == opportunity.title ? translatedText(for: .init(listingID: opportunity.id, field: "title", source: text, sourceHint: opportunity.description)) : text
    }

    func organization(for opportunity: Opportunity) -> String {
        let text = opportunity.localizedOrganization(language: language)
        return text == opportunity.organization ? translatedText(for: .init(listingID: opportunity.id, field: "organization", source: text, sourceHint: opportunity.description)) : text
    }

    func city(for opportunity: Opportunity) -> String {
        let text = opportunity.localizedCity(language: language)
        return text == opportunity.city ? translatedText(for: .init(listingID: opportunity.id, field: "city", source: text, sourceHint: opportunity.description)) : text
    }

    func region(for opportunity: Opportunity) -> String {
        opportunity.localizedRegion(language: language)
    }

    func categoryName(for opportunity: Opportunity) -> String {
        let localizedCategory = opportunity.localizedCategory(language: language)
        return localizedCategory == opportunity.category ? categoryName(opportunity.category) : localizedCategory
    }

    func cost(for opportunity: Opportunity) -> String {
        let localizedCost = opportunity.localizedCost(language: language)
        let normalized = localizedCost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["free", "free to join"].contains(normalized) ? text("freeCost") : localizedCost
    }

    func categoryName(_ category: String) -> String {
        let key = "category" + category
            .replacingOccurrences(of: "&", with: "And")
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        let localized = text(key)
        return localized == key ? category : localized
    }

    func fullDescription(for opportunity: Opportunity) -> String {
        let text = opportunity.localizedDescription(language: language)
        return text == opportunity.description ? translatedText(for: .init(listingID: opportunity.id, field: "description", source: text)) : text
    }

    func summary(for opportunity: Opportunity) -> String {
        opportunity.localizedSummary(language: language)
    }

    func formattedDate(_ value: String?) -> String {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return ""
        }
        guard let date = FeedFreshness.date(from: trimmedValue) else { return trimmedValue }
        return Self.displayDateFormatter(
            for: language,
            preservesCalendarDate: Self.isDateOnlyValue(trimmedValue)
        ).string(from: date)
    }

    func formattedEventDateTime(_ value: String?) -> String {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return ""
        }
        guard let date = FeedFreshness.date(from: trimmedValue) else { return trimmedValue }
        let isDateOnly = Self.isDateOnlyValue(trimmedValue)
        return Self.eventDateFormatter(
            for: language,
            includesTime: !isDateOnly,
            timeZone: isDateOnly
                ? TimeZone(secondsFromGMT: 0)
                : Self.encodedTimeZone(from: trimmedValue)
        ).string(from: date)
    }

    /// GTA program times are shown in Toronto, including the offset on the event day.
    /// Date-only values remain calendar dates; a missing schedule remains missing.
    func formattedLocalEventDateTime(_ value: String?) -> String {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "" }
        guard let date = FeedFreshness.date(from: raw) else { return raw }
        if Self.isDateOnlyValue(raw) { return formattedEventDateTime(raw) }
        let zone = TimeZone(identifier: "America/Toronto")!
        let text = Self.eventDateFormatter(for: language, includesTime: true, timeZone: zone).string(from: date)
        return "\(text) \(zone.abbreviation(for: date) ?? "Toronto")"
    }

    func formattedSchedule(start: String?, end: String?) -> String? {
        let startText = formattedLocalEventDateTime(start)
        let endText = formattedLocalEventDateTime(end)
        switch (startText.isEmpty, endText.isEmpty) {
        case (true, true): return nil
        case (false, true): return startText
        case (true, false): return endText
        case (false, false):
            guard startText != endText else { return startText }
            guard let startValue = start?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let endValue = end?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !Self.isDateOnlyValue(startValue), !Self.isDateOnlyValue(endValue),
                  let startDate = FeedFreshness.date(from: startValue),
                  let endDate = FeedFreshness.date(from: endValue)
            else { return "\(startText) – \(endText)" }
            let zone = TimeZone(identifier: "America/Toronto")!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            guard calendar.isDate(startDate, inSameDayAs: endDate),
                  zone.secondsFromGMT(for: startDate) == zone.secondsFromGMT(for: endDate)
            else { return "\(startText) – \(endText)" }
            let dateText = Self.eventDateFormatter(for: language, includesTime: false, timeZone: zone).string(from: startDate)
            let times = Self.eventTimeFormatter(for: language, timeZone: zone)
            return "\(dateText) · \(times.string(from: startDate))–\(times.string(from: endDate)) \(zone.abbreviation(for: endDate) ?? "Toronto")"
        }
    }

    func saveLocalProfile(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        displayName = trimmedName
        defaults.set(trimmedName, forKey: Self.localProfileNameKey)
        defaults.set(true, forKey: Self.localProfileEnabledKey)
    }

    func clearLocalProfile() {
        defaults.removeObject(forKey: Self.localProfileNameKey)
        defaults.set(false, forKey: Self.localProfileEnabledKey)
        displayName = text("guest")
    }

    private static func displayDateFormatter(for language: AppLanguage, preservesCalendarDate: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: language.localeIdentifier)
        // Feed freshness can be a calendar date (for example, "2026-08-06")
        // rather than a moment in time. Keep that declared day stable for GTA
        // users in negative UTC offsets instead of rendering it as Aug 5.
        if preservesCalendarDate {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }
        return formatter
    }

    private static func eventDateFormatter(
        for language: AppLanguage,
        includesTime: Bool,
        timeZone: TimeZone?
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = includesTime ? .short : .none
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeZone = timeZone ?? .current
        return formatter
    }

    private static func eventTimeFormatter(for language: AppLanguage, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeZone = timeZone
        return formatter
    }

    private static func encodedTimeZone(from value: String) -> TimeZone? {
        if value.hasSuffix("Z") || value.hasSuffix("z") {
            return TimeZone(secondsFromGMT: 0)
        }

        let pattern = #"([+-])(\d{2}):?(\d{2})$"#
        guard let match = value.range(of: pattern, options: .regularExpression) else { return nil }
        let suffix = String(value[match])
        guard suffix.count == 6 || suffix.count == 5 else { return nil }
        let sign = suffix.first == "-" ? -1 : 1
        let digits = suffix.dropFirst().filter(\.isNumber)
        guard digits.count == 4,
              let hours = Int(String(digits.prefix(2))),
              let minutes = Int(String(digits.suffix(2))),
              hours <= 23,
              minutes <= 59
        else { return nil }
        return TimeZone(secondsFromGMT: sign * ((hours * 60 + minutes) * 60))
    }

    private static func isDateOnlyValue(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

// Demand is tied to visible surfaces. One host serializes small batches for the
// selected language; no catalog-wide translation or network service is started.
extension SessionStore {
    func prepareSmallSourceTranslations() async {
        guard !smallSourceBundleLoaded else { return }
        if smallSourceBundleTask == nil {
            let url = AppResources.url(forResource: "source-bound-small-translations", withExtension: "json")
            smallSourceBundleTask = Task.detached(priority: .utility) {
                guard let url, let data = try? Data(contentsOf: url) else { return nil }
                return SourceBoundSmallTranslations.decode(data, expectedSHA256: "d7a432e05c358bba848e05e00a2c1b9685641668e3fdc3f2fe7316580a97d0f8")
            }
        }
        let result = await smallSourceBundleTask?.value
        guard !smallSourceBundleLoaded else { return }
        smallSourceBundleLoaded = true
        smallSourceBundle = result ?? nil
        smallSourceBundleTask = nil
        translationRevision &+= 1
        translationWorkRevision &+= 1
    }
    private func smallSourceText(_ input: ListingTranslationInput) -> String? {
#if DEBUG
        if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-translation-fixture") { return nil }
#endif
        return smallSourceBundle?.resolve(input, language: language)
    }
    func setTranslationDemand(owner: UUID, inputs: [ListingTranslationInput], priority: Int = 0) {
        var bytes = 0
        var bounded: [ListingTranslationInput] = []
        for input in inputs {
            let size = input.source.utf8.count + (input.sourceHint?.utf8.count ?? 0)
            guard !input.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard bounded.count < 40, input.source.utf8.count <= 100_000,
                  bytes + size <= 240_000 else {
                rememberTranslation(.unavailable, key: input.key(target: language.localeIdentifier))
                continue
            }
            bytes += size
            bounded.append(input)
        }
        if let current = translationDemands[owner], current.inputs == bounded, current.priority == priority { return }
        translationDemandOrder += 1
        translationDemands[owner] = TranslationDemand(inputs: bounded, priority: priority, order: translationDemandOrder)
        while translationDemands.count > 48 {
            guard let oldest = translationDemands.min(by: { $0.value.order < $1.value.order })?.key else { break }
            translationDemands.removeValue(forKey: oldest)
        }
        pruneUndemandedTranslationStates()
        translationWorkRevision &+= 1
    }

    func removeTranslationDemand(owner: UUID) {
        guard translationDemands.removeValue(forKey: owner) != nil else { return }
        pruneUndemandedTranslationStates()
        translationWorkRevision &+= 1
    }

    func translatedText(for input: ListingTranslationInput) -> String {
        smallSourceText(input) ?? translationValues[input.key(target: language.localeIdentifier)] ?? input.source
    }

    func translationState(for input: ListingTranslationInput) -> ListingTranslationState {
        if input.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .original }
        if smallSourceText(input) != nil { return .translated }
#if canImport(Translation)
        if #available(iOS 18.0, macCatalyst 26.0, *) {
            return translationStates[input.key(target: language.localeIdentifier)] ?? .waiting
        }
#endif
        if let source = Self.detectTranslationSource(input), Self.translationLanguagesMatch(source, language.localeIdentifier) {
            return .original
        }
        return .unavailable
    }

    func retryTranslations() {
        for key in Array(translationStates.keys) where key.targetLocale == language.localeIdentifier {
            if translationStates[key] == .failed || translationStates[key] == .unavailable {
                translationStates.removeValue(forKey: key)
                translationResultOrder.removeAll { $0 == key }
            }
        }
        translationRevision &+= 1
        translationWorkRevision &+= 1
    }

    private func translationLanguageChanged() {
        activeTranslationBatch = nil
        for key in Array(translationStates.keys) where translationStates[key] == .waiting {
            translationStates.removeValue(forKey: key)
        }
        pruneUndemandedTranslationStates()
        translationRevision &+= 1
        translationWorkRevision &+= 1
    }

    func prepareTranslationDetections() async -> Bool {
        let revision = translationWorkRevision
        let target = language.localeIdentifier
        var seen = Set<ListingTranslationKey>()
        var inputs: [ListingTranslationInput] = []
        for demand in translationDemands.values.sorted(by: {
            $0.priority == $1.priority ? $0.order < $1.order : $0.priority > $1.priority
        }) {
            for input in demand.inputs {
                let key = input.key(target: target)
                guard seen.insert(key).inserted, translationStates[key] == nil, smallSourceText(input) == nil else { continue }
                inputs.append(input)
                if inputs.count == 12 { break }
            }
            if inputs.count == 12 { break }
        }
        let missing = inputs.filter { sourceDetectionCache[$0.key(target: "source-detection")] == nil }
        if !missing.isEmpty {
            let detected = await Task.detached(priority: .userInitiated) {
                missing.map { input -> (ListingTranslationKey, SourceDetection) in
                    let result = Self.detectTranslationSource(input).map(SourceDetection.language) ?? .unavailable
                    return (input.key(target: "source-detection"), result)
                }
            }.value
            guard !Task.isCancelled, revision == translationWorkRevision, target == language.localeIdentifier else { return false }
            for (key, result) in detected {
                sourceDetectionCache[key] = result
                sourceDetectionOrder.removeAll { $0 == key }
                sourceDetectionOrder.append(key)
            }
            while sourceDetectionOrder.count > 256 {
                sourceDetectionCache.removeValue(forKey: sourceDetectionOrder.removeFirst())
            }
        }
        return !Task.isCancelled && revision == translationWorkRevision && target == language.localeIdentifier
    }

    func nextTranslationBatch(allowSynchronousDetection: Bool = true) -> ListingTranslationBatch? {
        guard activeTranslationBatch == nil else { return nil }
        var seen = Set<ListingTranslationKey>()
        var selected: [ListingTranslationInput] = []
        var sourceLanguage: String?
        var bytes = 0
        let target = language.localeIdentifier
        var examined = 0
        for demand in translationDemands.values.sorted(by: {
            $0.priority == $1.priority ? $0.order < $1.order : $0.priority > $1.priority
        }) {
            for input in demand.inputs {
                let key = input.key(target: target)
                guard seen.insert(key).inserted, translationStates[key] == nil, smallSourceText(input) == nil else { continue }
                examined += 1
                guard examined <= 12 else { break }
                let cached = sourceDetectionCache[input.key(target: "source-detection")]
                guard let detection = cached ?? (allowSynchronousDetection
                    ? (Self.detectTranslationSource(input).map(SourceDetection.language) ?? .unavailable)
                    : nil) else {
                    translationWorkRevision &+= 1
                    return nil
                }
                guard case .language(let source) = detection else {
                    rememberTranslation(.unavailable, key: key)
                    continue
                }
                if Self.translationLanguagesMatch(source, target) {
                    rememberTranslation(.original, key: key)
                    continue
                }
                if let first = sourceLanguage, first != source { continue }
                guard selected.count < 8, selected.isEmpty || bytes + input.source.utf8.count <= 24_000 else { continue }
                sourceLanguage = source
                bytes += input.source.utf8.count
                selected.append(input)
            }
        }
        if examined > 0 { translationRevision &+= 1 }
        guard let sourceLanguage, !selected.isEmpty else {
            // All examined items may already be in the selected language (or
            // unavailable). Continue bounded classification of any remainder.
            if examined > 12 { translationWorkRevision &+= 1 }
            return nil
        }
        let batch = ListingTranslationBatch(id: UUID(), target: target, sourceLanguage: sourceLanguage, inputs: selected)
        activeTranslationBatch = batch.id
        for input in selected { translationStates[input.key(target: target)] = .waiting }
        return batch
    }

    func isTranslationBatchDemanded(_ batch: ListingTranslationBatch) -> Bool {
        guard activeTranslationBatch == batch.id, language.localeIdentifier == batch.target else { return false }
        let demanded = Set(translationDemands.values.flatMap(\.inputs).map { $0.key(target: batch.target) })
        return batch.inputs.contains { demanded.contains($0.key(target: batch.target)) }
    }

    func finishTranslationBatch(_ batch: ListingTranslationBatch, results: [String: String], failure: ListingTranslationState? = nil) {
        guard activeTranslationBatch == batch.id, language.localeIdentifier == batch.target else { return }
        activeTranslationBatch = nil
        let demanded = Set(translationDemands.values.flatMap(\.inputs).map { $0.key(target: batch.target) })
        for (index, input) in batch.inputs.enumerated() {
            let key = input.key(target: batch.target)
            guard demanded.contains(key) else { translationStates.removeValue(forKey: key); continue }
            if let text = results[String(index)], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.utf8.count <= 600_000 {
                translationValues[key] = text
                rememberTranslation(.translated, key: key)
            } else {
                rememberTranslation(failure ?? .failed, key: key)
            }
        }
        translationRevision &+= 1
        translationWorkRevision &+= 1
    }

    func abandonTranslationBatch(_ batch: ListingTranslationBatch) {
        guard activeTranslationBatch == batch.id else { return }
        activeTranslationBatch = nil
        for input in batch.inputs where translationStates[input.key(target: batch.target)] == .waiting {
            translationStates.removeValue(forKey: input.key(target: batch.target))
        }
        translationWorkRevision &+= 1
    }

    private func rememberTranslation(_ state: ListingTranslationState, key: ListingTranslationKey) {
        translationStates[key] = state
        translationResultOrder.removeAll { $0 == key }
        translationResultOrder.append(key)
        guard translationResultOrder.count > 256 || translationValues.values.reduce(0, { $0 + $1.utf8.count }) > 1_200_000 else { return }
        let demanded = demandedTranslationKeys()
        while translationResultOrder.count > 256 || translationValues.values.reduce(0, { $0 + $1.utf8.count }) > 1_200_000 {
            let oldest = translationResultOrder.removeFirst()
            let evictedValue = translationValues.removeValue(forKey: oldest)
            if demanded.contains(oldest) {
                // Keep classifications for currently visible demand. Never
                // claim a translation whose cached text has been evicted.
                if evictedValue != nil { translationStates[oldest] = .failed }
            } else {
                translationStates.removeValue(forKey: oldest)
            }
        }
    }

    private func demandedTranslationKeys() -> Set<ListingTranslationKey> {
        let target = language.localeIdentifier
        return Set(translationDemands.values.flatMap(\.inputs).map { $0.key(target: target) })
    }

    private func pruneUndemandedTranslationStates() {
        let keep = demandedTranslationKeys().union(translationResultOrder)
        translationStates = translationStates.filter { keep.contains($0.key) }
    }

    nonisolated static func detectTranslationSource(_ input: ListingTranslationInput) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(input.source.prefix(8_000)))
        let primary = recognizer.dominantLanguage
        let confidence = primary.flatMap { recognizer.languageHypotheses(withMaximum: 1)[$0] } ?? 0
        // Detect the field itself first: a French title can accompany an
        // English description. Use body text only for short or ambiguous names,
        // never the programme's delivery-language metadata.
        if input.source.count >= 20, confidence >= 0.8 { return primary?.rawValue }
        guard let hint = input.sourceHint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return primary?.rawValue
        }
        recognizer.reset()
        recognizer.processString(String(hint.prefix(8_000)))
        return recognizer.dominantLanguage?.rawValue ?? primary?.rawValue
    }

    nonisolated static func translationLanguagesMatch(_ source: String, _ target: String) -> Bool {
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        guard sourceLanguage.languageCode == targetLanguage.languageCode else { return false }
        if sourceLanguage.languageCode?.identifier == "zh" {
            return sourceLanguage.maximalIdentifier == targetLanguage.maximalIdentifier
        }
        return true
    }

    nonisolated static func acceptsTranslationTarget(requested: String, returned: String) -> Bool {
        let request = Locale.Language(identifier: requested)
        let result = Locale.Language(identifier: returned)
        let requestCode = request.languageCode?.identifier.lowercased() ?? ""
        let resultCode = result.languageCode?.identifier.lowercased() ?? ""
        let returnedTag = returned.replacingOccurrences(of: "_", with: "-").lowercased()
        if requestCode == "yue" {
            return resultCode == "yue" || returnedTag == "zh-hk"
        }
        if requestCode == "zh" {
            guard resultCode == "zh", returnedTag != "zh-hk", returnedTag != "zh-tw" else { return false }
            return result.script?.identifier.lowercased() != "hant"
        }
        if requestCode == "fil" || requestCode == "tl" { return resultCode == "fil" || resultCode == "tl" }
        return !requestCode.isEmpty && requestCode == resultCode
    }
}

#if canImport(Translation)
struct ListingTranslationHost: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            if #available(iOS 18.0, macCatalyst 26.0, *) {
                ActiveListingTranslationHost().id(session.language)
            }
        }
        .task { await session.prepareSmallSourceTranslations() }
    }
}

@available(iOS 18.0, macCatalyst 26.0, *)
private struct ActiveListingTranslationHost: View {
    @EnvironmentObject private var session: SessionStore
    @State private var batch: ListingTranslationBatch?
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        let current = batch
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .task(id: session.translationWorkRevision) {
                if let current = batch {
                    guard !session.isTranslationBatchDemanded(current) else { return }
                    batch = nil
                    configuration = nil
                    session.abandonTranslationBatch(current)
                    return
                }
                // Coalesce rows appearing in one layout pass before requesting
                // a batch, without blocking UI interaction.
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                await beginNextBatch()
            }
            .translationTask(configuration) { @Sendable translator in
                guard let current else { return }
                do {
                    guard let plan = ListingTranslationPlan.make(current.inputs) else {
                        await MainActor.run {
                            guard batch?.id == current.id else { return }
                            session.finishTranslationBatch(current, results: [:], failure: .failed)
                            batch = nil
                            configuration = nil
                        }
                        return
                    }
                    let requests = plan.requests.map { TranslationSession.Request(sourceText: $0.source, clientIdentifier: $0.id) }
                    let responses = try await translator.translations(from: requests)
                    guard !Task.isCancelled else { return }
                    var pieces: [ListingTranslationPlan.Result] = []
                    for response in responses {
                        if let id = response.clientIdentifier,
                           SessionStore.acceptsTranslationTarget(requested: current.target, returned: response.targetLanguage.minimalIdentifier) {
                            pieces.append(.init(id: id, source: response.sourceText, target: response.targetText))
                        }
                    }
                    let output = plan.assemble(pieces)
                    await MainActor.run {
                        guard batch?.id == current.id else { return }
                        session.finishTranslationBatch(current, results: output)
                        batch = nil
                        configuration = nil
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard batch?.id == current.id else { return }
                        session.finishTranslationBatch(current, results: [:], failure: .failed)
                        batch = nil
                        configuration = nil
                    }
                }
            }
            .onDisappear {
                if let batch { session.abandonTranslationBatch(batch) }
                batch = nil
                configuration = nil
            }
    }

    // Keep the non-Sendable Apple availability object within one nonisolated
    // operation; only its Sendable status crosses back to the view actor.
    nonisolated private static func availability(source: String, target: String) async -> LanguageAvailability.Status {
        let availability: LanguageAvailability
        if #available(iOS 26.4, macCatalyst 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: .highFidelity)
        } else {
            availability = LanguageAvailability()
        }
        if target == "yue-Hant" {
            let supported = await availability.supportedLanguages
            let hasExactYue = supported.contains { $0.languageCode?.identifier == "yue" }
            let hasHongKongChinese = supported.contains { $0.minimalIdentifier.replacingOccurrences(of: "_", with: "-").lowercased() == "zh-hk" }
            if #available(iOS 26.4, macCatalyst 26.4, *) {
                guard hasExactYue || hasHongKongChinese else { return .unsupported }
            } else {
                guard hasExactYue else { return .unsupported }
            }
        }
        return await availability.status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
    }

    private func beginNextBatch() async {
        await session.prepareSmallSourceTranslations()
        guard !Task.isCancelled, batch == nil, await session.prepareTranslationDetections(), !Task.isCancelled,
              batch == nil, let next = session.nextTranslationBatch(allowSynchronousDetection: false) else { return }
        batch = next
#if DEBUG
        if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-mac-translation-replay") {
            var output: [String: String] = [:]
            for (index, input) in next.inputs.enumerated() {
                if let text = MacTranslationLayoutReplay.text(for: input, locale: next.target) { output[String(index)] = text }
            }
            session.finishTranslationBatch(next, results: output, failure: .unavailable)
            batch = nil
            return
        }
        if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-translation-fixture-hold") {
            return
        }
        if AppRuntime.isFrontendLayoutReview && ProcessInfo.processInfo.arguments.contains("-review-translation-fixture") {
            let output = Dictionary(uniqueKeysWithValues: next.inputs.enumerated().map {
                (String($0.offset), "[LAYOUT FIXTURE \(next.target)] \($0.element.source)")
            })
            session.finishTranslationBatch(next, results: output)
            batch = nil
            return
        }
#endif
        let source = Locale.Language(identifier: next.sourceLanguage)
        let target = Locale.Language(identifier: next.target)
        let status = await Self.availability(source: next.sourceLanguage, target: next.target)
        guard !Task.isCancelled, batch?.id == next.id else {
            session.abandonTranslationBatch(next)
            if batch?.id == next.id { batch = nil }
            return
        }
        switch status {
        case .installed, .supported:
            if #available(iOS 26.4, macCatalyst 26.4, *) {
                configuration = .init(source: source, target: target, preferredStrategy: .highFidelity)
            } else {
                configuration = .init(source: source, target: target)
            }
        case .unsupported:
            session.finishTranslationBatch(next, results: [:], failure: .unavailable)
            batch = nil
        @unknown default:
            session.finishTranslationBatch(next, results: [:], failure: .unavailable)
            batch = nil
        }
    }
}
#else
struct ListingTranslationHost: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View { Color.clear.frame(width: 0, height: 0).task { await session.prepareSmallSourceTranslations() } }
}
#endif

#if DEBUG
/// Actual Mac Translation output, recorded solely for isolated UI layout tests.
/// This is not an iPhone translation or a semantic accuracy endorsement.
enum MacTranslationLayoutReplay {
    static let id = "tpl-rss-6a2afd9cf56bd86e00b61de1"
    static let titleHash = "c70dcdf7529af12b53369795b746ab9ce9ea16b679dd5ba683f9b211202a89c0"
    static let descriptionHash = "e54d96f85e58beca32d9ccc842f242e7cb731dd55e4fed2042f417568cb44c7a"
    static func text(for input: ListingTranslationInput, locale: String) -> String? {
        guard input.listingID == id else { return nil }
        let expected = input.field == "title" ? titleHash : input.field == "description" ? descriptionHash : ""
        guard !expected.isEmpty, FullDescriptionBinding.hash(input.source) == expected else { return nil }
        switch (locale, input.field) {
        case ("zh-Hans", "title"): return "数据分析基础学习圈"
        case ("zh-Hans", "description"): return "有兴趣了解数据分析吗？ 让我们在一个充满欢迎氛围的空间里一起参加免费的在线课程！ 学习圈是一个由图书馆工作人员指导的研讨小组，旨在为希望在支持性和欢迎性的环境中一起参加免费在线课程的人士提供学习机会。 世界各地的组织都认识到分析的重要性。 一起，我们将了解该领域中使用的基本工具。 在这个为期12周的学习圈中，我们将学习来自Cisco Networking Academy的数据分析基础课程。 我们将探讨数据分析师的基本工具，包括如何：使用Excel等电子表格工具转换、组织和可视化数据；使用SQL从关系数据库中查询数据；使用Tableau等商业智能工具改进数据呈现。我们将每周两次，于9月15日至12月8日（星期二下午2:00至3:30）面对面见面（共12节课）。 参与者应承诺遵守课程的持续时间，并每周参加一次课程。 完成课程的学习者将能够：获得数字徽章 下载完成证书"
        case ("fr", "title"): return "Cercles d'apprentissage essentiels en analyse de données"
        case ("fr", "description"): return "Vous êtes intéressé(e) à en savoir plus sur l'analyse de données ? Prenons ensemble un cours en ligne gratuit dans un espace accueillant ! Un cercle d'apprentissage est un groupe d'étude encadré par le personnel de la bibliothèque pour les personnes qui souhaitent suivre ensemble un cours en ligne gratuit dans un environnement bienveillant et accueillant. Les organisations du monde entier reconnaissent la valeur de l'analyse. Ensemble, nous découvrirons les outils essentiels utilisés dans ce domaine. Dans ce cercle d'apprentissage de 12 semaines, nous suivrons le cours Essentials d'analyse de données de Cisco Networking Academy. Nous explorerons les outils fondamentaux d'un analyste de données, y compris comment : transformer, organiser et visualiser les données à l'aide d'outils de tableurs comme Excel, interroger des données à partir d'une base de données relationnelle en utilisant SQL, améliorer les présentations de données à l'aide d'outils d'intelligence d'affaires comme Tableau. Nous nous rencontrerons en personne chaque mardi après-midi, du 15 septembre au 8 décembre, de 14h00 à 15h30 (12 sessions). Les participants sont tenus de s'engager dans la durée du cours et de assister aux séances chaque semaine. Les apprenants qui terminent le cours pourront : obtenir un badge numérique et télécharger un certificat de réussite."
        case ("ar", "title"): return "دائرة التعلم الأساسية لتحليل البيانات"
        case ("ar", "description"): return "هل أنت مهتم بالتعرف على تحليل البيانات؟ دعنا نأخذ دورة عبر الإنترنت مجانية معًا في مساحة مرحبة! الدائرة التعلمية هي مجموعة دراسية تُوجّه من قبل موظفي المكتبة، للأشخاص الذين يرغبون في حضور دورة عبر الإنترنت مجانية معًا في بيئة داعمة ومرحبة. تدرك المنظمات في جميع أنحاء العالم قيمة التحليلات. معًا، سنتعلم عن الأدوات الأساسية المستخدمة في هذا المجال. في هذه الدائرة التعلمية التي تستمر لمدة 12 أسبوعًا، سنعمل على دورة أساسيات تحليل البيانات من Cisco Networking Academy. سنستكشف الأدوات الأساسية لتحليل البيانات، بما في ذلك كيفية: تحويل البيانات وتنظيمها وتصورها باستخدام أدوات جداول البيانات مثل Excel، واستخراج البيانات من قاعدة بيانات علاقات باستخدام SQL، وتحسين عروض البيانات باستخدام أدوات الذكاء الاصطناعي التجاري مثل Tableau. سنلتقي أسبوعيًا شخصيًا كل يوم الثلاثاء بعد الظهر، من 15 سبتمبر إلى 8 ديسمبر، من الساعة 2:00 إلى 3:30 مساءً (12 جلسة). من المتوقع أن يلتزم المشاركون بفترة مدة الدورة ويحضروا الجلسات بشكل أسبوعي. سيتمكن المتعلمون الذين يكملون الدورة من: الحصول على شارة رقمية وتنزيل شهادة الإكمال."
        default: return nil
        }
    }
}
#endif
