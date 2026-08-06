import Foundation

/// Shared feed-age policy for every remote opportunity source, including the
/// watch companion. A successful HTTP response is not enough to call data live.
enum FeedFreshness {
    static let maximumRemoteFeedAge: TimeInterval = 60 * 60 * 24 * 14

    static func isCurrent(
        _ lastUpdated: String?,
        now: Date = .now,
        maximumAge: TimeInterval = maximumRemoteFeedAge
    ) -> Bool {
        guard let date = date(from: lastUpdated) else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age <= maximumAge
    }

    static func date(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: value) {
            return date
        }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }
}
