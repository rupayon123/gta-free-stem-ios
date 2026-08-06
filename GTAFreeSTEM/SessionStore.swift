import SwiftUI

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
        opportunity.localizedTitle(language: language)
    }

    func organization(for opportunity: Opportunity) -> String {
        opportunity.localizedOrganization(language: language)
    }

    func city(for opportunity: Opportunity) -> String {
        opportunity.localizedCity(language: language)
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
        return localizedCost.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("free") == .orderedSame ? text("freeAccessible") : localizedCost
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

    func formattedSchedule(start: String?, end: String?) -> String? {
        let startText = formattedEventDateTime(start)
        let endText = formattedEventDateTime(end)
        switch (startText.isEmpty, endText.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return startText
        case (true, false):
            return endText
        case (false, false):
            guard startText != endText else { return startText }
            guard let startValue = start?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let endValue = end?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !Self.isDateOnlyValue(startValue),
                  !Self.isDateOnlyValue(endValue),
                  let startDate = FeedFreshness.date(from: startValue),
                  let endDate = FeedFreshness.date(from: endValue),
                  let startZone = Self.encodedTimeZone(from: startValue),
                  let endZone = Self.encodedTimeZone(from: endValue),
                  startZone.secondsFromGMT(for: startDate) == endZone.secondsFromGMT(for: endDate)
            else {
                return "\(startText) – \(endText)"
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = startZone
            guard calendar.isDate(startDate, inSameDayAs: endDate) else {
                return "\(startText) – \(endText)"
            }

            let dateText = Self.eventDateFormatter(
                for: language,
                includesTime: false,
                timeZone: startZone
            ).string(from: startDate)
            let timeFormatter = Self.eventTimeFormatter(for: language, timeZone: startZone)
            return "\(dateText) · \(timeFormatter.string(from: startDate))–\(timeFormatter.string(from: endDate))"
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
