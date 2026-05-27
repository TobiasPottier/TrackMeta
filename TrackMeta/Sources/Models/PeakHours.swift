import Foundation

/// Anthropic's Claude service experiences higher demand during US business hours.
/// Per Anthropic's documentation, peak usage is on weekdays between roughly
/// 9 AM and 9 PM Eastern time — requests during this window are more likely
/// to be throttled and count more aggressively against rate limits.
struct PeakHoursWindow: Equatable {
    let startHour: Int          // 0–23, inclusive
    let endHour: Int            // 0–23, exclusive
    let weekdaysOnly: Bool
    let timeZone: TimeZone

    static let claudeDefault = PeakHoursWindow(
        startHour: 14,
        endHour: 20,
        weekdaysOnly: true,
        timeZone: TimeZone(identifier: "Europe/Brussels") ?? .current
    )

    func status(at date: Date = Date()) -> PeakHoursStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let weekday = calendar.component(.weekday, from: date) // 1=Sun, 7=Sat
        let isWeekday = (weekday >= 2 && weekday <= 6)
        let hour = calendar.component(.hour, from: date)

        let inHourRange = hour >= startHour && hour < endHour
        let isPeakDay = weekdaysOnly ? isWeekday : true
        let isPeakNow = isPeakDay && inHourRange

        return PeakHoursStatus(
            isPeakNow: isPeakNow,
            nextBoundary: nextBoundary(from: date, calendar: calendar, isPeakNow: isPeakNow),
            window: self
        )
    }

    private func nextBoundary(
        from date: Date,
        calendar: Calendar,
        isPeakNow: Bool
    ) -> Date? {
        let targetHour = isPeakNow ? endHour : startHour
        var probe = date
        for _ in 0..<14 {
            guard let candidate = calendar.nextDate(
                after: probe,
                matching: DateComponents(hour: targetHour, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { return nil }

            let weekday = calendar.component(.weekday, from: candidate)
            let isWeekday = (weekday >= 2 && weekday <= 6)

            if isPeakNow {
                // looking for end of current peak — same day, must still be a peak day
                if !weekdaysOnly || isWeekday {
                    return candidate
                }
            } else {
                // looking for start of next peak — must land on a peak day
                if !weekdaysOnly || isWeekday {
                    return candidate
                }
            }
            probe = candidate
        }
        return nil
    }

    func formattedWindow() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        formatter.timeZone = timeZone
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"

        var components = DateComponents()
        components.hour = startHour
        let startDate = Calendar.current.date(from: components) ?? Date()
        components.hour = endHour
        let endDate = Calendar.current.date(from: components) ?? Date()

        let tzAbbrev = timeZone.abbreviation(for: Date()) ?? timeZone.identifier
        let days = weekdaysOnly ? "Mon–Fri" : "Daily"
        return "\(days) · \(formatter.string(from: startDate))–\(formatter.string(from: endDate)) \(tzAbbrev)"
    }
}

struct PeakHoursStatus: Equatable {
    let isPeakNow: Bool
    let nextBoundary: Date?
    let window: PeakHoursWindow
}
