import Foundation
import EventKit

enum CalendarStartWeekMode: String, CaseIterable, Identifiable {
    case currentWeek = "CURRENT"
    case nextMonday = "NEXT_MONDAY"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .currentWeek: return "Bieżący tydzień"
        case .nextMonday: return "Od przyszłego poniedziałku"
        }
    }
}

enum CalendarRecurrenceMode: String, CaseIterable, Identifiable {
    case singleWeek = "SINGLE"
    case next16Weeks = "16_WEEKS"
    case untilEndOfSchoolYear = "END_OF_YEAR"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .singleWeek: return "Tylko wybrany tydzień"
        case .next16Weeks: return "Powtarzaj przez 16 tygodni"
        case .untilEndOfSchoolYear: return "Do końca roku szkolnego (30 czerwca)"
        }
    }
}

enum CalendarExportError: LocalizedError {
    case accessDenied
    case noLessonsToExport
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Brak uprawnień do Kalendarza Apple. Zezwól na dostęp w Ustawieniach iOS."
        case .noLessonsToExport:
            return "Brak lekcji do wyeksportowania dla wybranych filtrów."
        case .saveFailed(let msg):
            return "Błąd zapisu do kalendarza: \(msg)"
        }
    }
}

final class CalendarExporter {
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { cont in
                store.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: granted)
                    }
                }
            }
        }
    }

    func exportToAppleCalendar(
        timetable: ClassTimetable,
        filteredLessonsByDay: [Int: [LessonEntry]],
        calendarTitle: String,
        startWeekMode: CalendarStartWeekMode,
        recurrenceMode: CalendarRecurrenceMode,
        replaceExisting: Bool = true
    ) async throws -> Int {
        let granted = try await requestAccess()
        guard granted else { throw CalendarExportError.accessDenied }

        let totalLessons = filteredLessonsByDay.values.reduce(0) { $0 + $1.count }
        guard totalLessons > 0 else { throw CalendarExportError.noLessonsToExport }

        let targetCalendar = try findOrCreateCalendar(title: calendarTitle, replaceExisting: replaceExisting)
        let mondayDate = computeWeekMonday(startWeekMode: startWeekMode)
        let recurrenceEnd = computeRecurrenceEndDate(weekMonday: mondayDate, mode: recurrenceMode)
        let warsawCal = Self.warsawCalendar()

        var createdCount = 0
        for (dayIdx, lessons) in filteredLessonsByDay where (0...4).contains(dayIdx) {
            guard let dayDate = warsawCal.date(byAdding: .day, value: dayIdx, to: mondayDate) else { continue }
            for lesson in lessons {
                let (startPair, endPair) = LiveScheduleTracker.parseTimeRange(lesson.timeRange, period: lesson.period)
                guard let startDate = warsawCal.date(bySettingHour: startPair.0, minute: startPair.1, second: 0, of: dayDate),
                      var endDate = warsawCal.date(bySettingHour: endPair.0, minute: endPair.1, second: 0, of: dayDate) else {
                    continue
                }
                if endDate <= startDate {
                    endDate = startDate.addingTimeInterval(45 * 60)
                }

                let event = EKEvent(eventStore: store)
                event.calendar = targetCalendar
                event.title = lesson.subject.isEmpty ? "Lekcja \(lesson.period)" : lesson.subject
                event.location = lesson.room.isEmpty ? nil : "Sala \(lesson.room)"
                var descParts: [String] = []
                if !lesson.teacher.isEmpty { descParts.append("Nauczyciel: \(lesson.teacher)") }
                if !lesson.classGroupLabel.isEmpty { descParts.append("Klasa: \(lesson.classGroupLabel)") }
                if let tag = lesson.groupTag { descParts.append("Grupa: \(tag)") }
                descParts.append("Lekcja nr \(lesson.period)")
                event.notes = descParts.joined(separator: "\n")
                event.startDate = startDate
                event.endDate = endDate
                event.timeZone = TimeZone(identifier: "Europe/Warsaw")

                if let untilDate = recurrenceEnd {
                    let rule = EKRecurrenceRule(
                        recurrenceWith: .weekly,
                        interval: 1,
                        end: EKRecurrenceEnd(end: untilDate)
                    )
                    event.addRecurrenceRule(rule)
                }

                try store.save(event, span: .thisEvent, commit: false)
                createdCount += 1
            }
        }

        do {
            try store.commit()
        } catch {
            throw CalendarExportError.saveFailed(error.localizedDescription)
        }
        return createdCount
    }

    func generateICSContent(
        timetable: ClassTimetable,
        filteredLessonsByDay: [Int: [LessonEntry]],
        startWeekMode: CalendarStartWeekMode,
        recurrenceMode: CalendarRecurrenceMode
    ) -> String {
        let monday = computeWeekMonday(startWeekMode: startWeekMode)
        let untilDate = computeRecurrenceEndDate(weekMonday: monday, mode: recurrenceMode)
        let warsawCal = Self.warsawCalendar()

        let localFmt = DateFormatter()
        localFmt.dateFormat = "yyyyMMdd'T'HHmmss"
        localFmt.timeZone = TimeZone(identifier: "Europe/Warsaw")

        let utcFmt = DateFormatter()
        utcFmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        utcFmt.timeZone = TimeZone(secondsFromGMT: 0)

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ZSME Assistant//iOS//PL",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:Plan lekcji — \(timetable.className)",
            "X-WR-TIMEZONE:Europe/Warsaw"
        ]

        for (dayIdx, lessons) in filteredLessonsByDay.sorted(by: { $0.key < $1.key }) where (0...4).contains(dayIdx) {
            guard let dayDate = warsawCal.date(byAdding: .day, value: dayIdx, to: monday) else { continue }
            for lesson in lessons {
                let (startPair, endPair) = LiveScheduleTracker.parseTimeRange(lesson.timeRange, period: lesson.period)
                guard let startDate = warsawCal.date(bySettingHour: startPair.0, minute: startPair.1, second: 0, of: dayDate),
                      var endDate = warsawCal.date(bySettingHour: endPair.0, minute: endPair.1, second: 0, of: dayDate) else {
                    continue
                }
                if endDate <= startDate { endDate = startDate.addingTimeInterval(45 * 60) }

                lines.append("BEGIN:VEVENT")
                lines.append("UID:\(UUID().uuidString)@zsme.pl")
                lines.append("DTSTAMP:\(utcFmt.string(from: Date()))")
                lines.append("DTSTART;TZID=Europe/Warsaw:\(localFmt.string(from: startDate))")
                lines.append("DTEND;TZID=Europe/Warsaw:\(localFmt.string(from: endDate))")
                if let until = untilDate {
                    lines.append("RRULE:FREQ=WEEKLY;UNTIL=\(utcFmt.string(from: until))")
                }
                lines.append("SUMMARY:\(lesson.subject)")
                if !lesson.room.isEmpty {
                    lines.append("LOCATION:Sala \(lesson.room)")
                }
                if !lesson.teacher.isEmpty {
                    lines.append("DESCRIPTION:Nauczyciel: \(lesson.teacher)")
                }
                lines.append("END:VEVENT")
            }
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private func findOrCreateCalendar(title: String, replaceExisting: Bool) throws -> EKCalendar {
        let existing = store.calendars(for: .event).first { $0.title == title && $0.allowsContentModifications }
        if let cal = existing {
            if replaceExisting {
                let start = Date().addingTimeInterval(-365 * 24 * 3600)
                let end = Date().addingTimeInterval(400 * 24 * 3600)
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
                for ev in store.events(matching: predicate) {
                    try? store.remove(ev, span: .futureEvents, commit: false)
                }
            }
            return cal
        }

        let newCal = EKCalendar(for: .event, eventStore: store)
        newCal.title = title
        if let iCloud = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("iCloud") }) {
            newCal.source = iCloud
        } else if let defaultSource = store.defaultCalendarForNewEvents?.source {
            newCal.source = defaultSource
        } else if let local = store.sources.first(where: { $0.sourceType == .local }) {
            newCal.source = local
        } else if let anySource = store.sources.first {
            newCal.source = anySource
        }
        try store.saveCalendar(newCal, commit: true)
        return newCal
    }

    private func computeWeekMonday(startWeekMode: CalendarStartWeekMode) -> Date {
        let cal = Self.warsawCalendar()
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let wd = cal.component(.weekday, from: startOfToday)
        let daysFromMonday: Int
        switch wd {
        case 2: daysFromMonday = 0
        case 3: daysFromMonday = 1
        case 4: daysFromMonday = 2
        case 5: daysFromMonday = 3
        case 6: daysFromMonday = 4
        case 7: daysFromMonday = 5
        default: daysFromMonday = 6
        }
        var monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfToday) ?? startOfToday
        if startWeekMode == .nextMonday {
            monday = cal.date(byAdding: .day, value: 7, to: monday) ?? monday
        }
        return monday
    }

    private func computeRecurrenceEndDate(weekMonday: Date, mode: CalendarRecurrenceMode) -> Date? {
        let cal = Self.warsawCalendar()
        switch mode {
        case .singleWeek:
            return nil
        case .next16Weeks:
            return cal.date(byAdding: .day, value: 16 * 7 - 1, to: weekMonday)
        case .untilEndOfSchoolYear:
            let month = cal.component(.month, from: weekMonday)
            let year = cal.component(.year, from: weekMonday)
            let targetYear = month >= 7 ? year + 1 : year
            var comps = DateComponents()
            comps.year = targetYear
            comps.month = 6
            comps.day = 30
            comps.hour = 23
            comps.minute = 59
            return cal.date(from: comps)
        }
    }

    private static func warsawCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current
        return cal
    }
}
