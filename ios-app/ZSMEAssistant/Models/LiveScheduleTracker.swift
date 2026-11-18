import Foundation

struct LiveLessonItem: Identifiable, Hashable {
    var id: String { "\(lesson.id)_\(substitution?.id ?? "none")" }
    let lesson: LessonEntry
    let substitution: SubstitutionItem?
}

struct LiveLessonSlot: Identifiable, Hashable {
    var id: String { "\(period)_\(startSecondOfDay)_\(endSecondOfDay)" }
    let period: Int
    let startSecondOfDay: Int
    let endSecondOfDay: Int
    let timeRangeLabel: String
    let items: [LiveLessonItem]
}

enum LiveScheduleStatus {
    case noTimetable
    case weekend(nextDayLabel: String?, nextDayFirstSlot: LiveLessonSlot?)
    case beforeLessons(firstSlot: LiveLessonSlot, remainingSeconds: Int)
    case duringLesson(currentSlot: LiveLessonSlot, remainingSeconds: Int, totalSeconds: Int, nextSlot: LiveLessonSlot?)
    case breakTime(previousSlot: LiveLessonSlot, nextSlot: LiveLessonSlot, remainingSeconds: Int, totalSeconds: Int)
    case afterLessons(nextDayLabel: String?, nextDayFirstSlot: LiveLessonSlot?)
}

struct PreparedDaySchedule: Equatable {
    static let empty = PreparedDaySchedule(
        hasTimetable: false,
        todayDayIndex: nil,
        todayDayName: nil,
        todaySlots: [],
        cancelledCountToday: 0,
        substitutionBanner: nil,
        nextDayLabel: nil,
        nextDayFirstSlot: nil
    )

    let hasTimetable: Bool
    let todayDayIndex: Int?
    let todayDayName: String?
    let todaySlots: [LiveLessonSlot]
    let cancelledCountToday: Int
    let substitutionBanner: String?
    let nextDayLabel: String?
    let nextDayFirstSlot: LiveLessonSlot?
}

struct LiveScheduleEvaluation {
    let status: LiveScheduleStatus
    let todayDayIndex: Int?
    let todayDayName: String?
    var todaySlots: [LiveLessonSlot] = []
    var cancelledCountToday: Int = 0
    var substitutionBanner: String? = nil
}

enum LiveScheduleTracker {
    private static let dayNames = ["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek"]
    private static let rangeRegex = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*:\\s*(\\d{2})\\s*[-–]\\s*(\\d{1,2})\\s*:\\s*(\\d{2})")
    private static let singleTimeRegex = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*:\\s*(\\d{2})")
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    static let defaultBellSlots: [Int: (start: (Int, Int), end: (Int, Int))] = [
        0: ((7, 10), (7, 55)),
        1: ((8, 0), (8, 45)),
        2: ((8, 55), (9, 40)),
        3: ((9, 50), (10, 35)),
        4: ((10, 50), (11, 35)),
        5: ((11, 45), (12, 30)),
        6: ((12, 40), (13, 25)),
        7: ((13, 35), (14, 20)),
        8: ((14, 25), (15, 10)),
        9: ((15, 15), (16, 0)),
        10: ((16, 5), (16, 50))
    ]

    static func parseTimeRange(_ timeRange: String, period: Int) -> (start: (Int, Int), end: (Int, Int)) {
        let clean = timeRange
            .replacingOccurrences(of: ".", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let regex = rangeRegex,
           let match = regex.firstMatch(in: clean, options: [], range: NSRange(clean.startIndex..<clean.endIndex, in: clean)),
           let r1 = Range(match.range(at: 1), in: clean),
           let r2 = Range(match.range(at: 2), in: clean),
           let r3 = Range(match.range(at: 3), in: clean),
           let r4 = Range(match.range(at: 4), in: clean),
           let sh = Int(clean[r1]), let sm = Int(clean[r2]),
           let eh = Int(clean[r3]), let em = Int(clean[r4]) {
            return ((min(max(sh, 0), 23), min(max(sm, 0), 59)),
                    (min(max(eh, 0), 23), min(max(em, 0), 59)))
        }

        if let regex = singleTimeRegex,
           let match = regex.firstMatch(in: clean, options: [], range: NSRange(clean.startIndex..<clean.endIndex, in: clean)),
           let r1 = Range(match.range(at: 1), in: clean),
           let r2 = Range(match.range(at: 2), in: clean),
           let sh = Int(clean[r1]), let sm = Int(clean[r2]) {
            let endTotal = sh * 60 + sm + 45
            return ((min(max(sh, 0), 23), min(max(sm, 0), 59)),
                    (min(endTotal / 60, 23), endTotal % 60))
        }

        if let bell = defaultBellSlots[period] {
            return bell
        }
        let baseMins = min(8 * 60 + max(period - 1, 0) * 55, 20 * 60)
        let endMins = min(baseMins + 45, 21 * 60)
        return ((baseMins / 60, baseMins % 60), (endMins / 60, endMins % 60))
    }

    static func prepareDaySchedule(
        timetable: ClassTimetable?,
        substitutions: SubstitutionsSnapshot?,
        userRole: UserRole,
        selectedClassName: String,
        selectedGroup: StudentGroup,
        customGroupFilter: String,
        teacherAbbr: String,
        teacherFullName: String = "",
        hiddenSchoolIds: Set<String> = [],
        now: Date = Date()
    ) -> PreparedDaySchedule {
        guard let timetable = timetable, timetable.days.contains(where: { !$0.lessons.isEmpty }) else {
            return .empty
        }

        let weekday = gregorianCalendar.component(.weekday, from: now)
        let todayDayIndex = ScheduleFilterMatcher.weekdayToZeroBasedIndex(weekday)
        let todayDayName = todayDayIndex.map { dayNames[$0] }

        func buildSlotsForDay(_ dayIdx: Int, applySubs: Bool) -> (slots: [LiveLessonSlot], cancelledCount: Int, banner: String?) {
            let rawLessons = timetable.days.first(where: { $0.dayIndex == dayIdx })?.lessons ?? []
            let schoolVisible = userRole == .teacher
                ? ScheduleFilterMatcher.filterLessonsByVisibleSchools(rawLessons, hiddenSchoolIds: hiddenSchoolIds)
                : rawLessons

            let filtered: [LessonEntry]
            if userRole == .teacher {
                filtered = schoolVisible
            } else {
                filtered = schoolVisible.filter { lesson in
                    ScheduleFilterMatcher.matchesGroup(
                        groupTag: lesson.groupTag,
                        combinedText: "\(lesson.subject) \(lesson.rawText)",
                        selectedGroup: selectedGroup,
                        customGroupFilter: customGroupFilter
                    )
                }
            }

            let classResolution: ClassDaySubstitutionResolution
            if applySubs && userRole != .teacher {
                classResolution = ScheduleFilterMatcher.resolveClassDaySubstitutions(
                    dayLessons: filtered,
                    dayIndex: dayIdx,
                    todayWeekdayIndex: todayDayIndex,
                    snapshot: substitutions,
                    className: selectedClassName,
                    selectedGroup: selectedGroup,
                    customGroupFilter: customGroupFilter
                )
            } else {
                classResolution = ClassDaySubstitutionResolution()
            }

            var activeItems: [LiveLessonItem] = []
            for (idx, lesson) in filtered.enumerated() {
                let sub: SubstitutionItem?
                if !applySubs {
                    sub = nil
                } else if userRole == .teacher {
                    sub = substitutions?.items.first { item in
                        ScheduleFilterMatcher.parseSubstitutionPeriods(item.period).contains(lesson.period) &&
                        ScheduleFilterMatcher.substitutionAppliesToDay(
                            dateLabel: item.dateLabel,
                            fallbackDateHeading: substitutions?.dateHeading ?? "",
                            dayIndex: dayIdx,
                            todayWeekdayIndex: todayDayIndex
                        ) &&
                        ScheduleFilterMatcher.matchesTeacherSubstitution(
                            item: item,
                            teacherAbbr: teacherAbbr,
                            teacherFullName: teacherFullName
                        ) == .replaced
                    }
                } else {
                    sub = classResolution.byLessonIndex[idx]
                }

                let isCancelled: Bool
                if userRole == .teacher {
                    isCancelled = sub != nil
                } else {
                    isCancelled = sub?.isCancellation == true
                }
                if !isCancelled {
                    activeItems.append(LiveLessonItem(lesson: lesson, substitution: sub))
                }
            }

            struct WindowKey: Hashable {
                let startSec: Int
                let endSec: Int
            }
            var grouped: [WindowKey: [LiveLessonItem]] = [:]
            for item in activeItems {
                let parsed = parseTimeRange(item.lesson.timeRange, period: item.lesson.period)
                let startSec = parsed.start.0 * 3600 + parsed.start.1 * 60
                var endSec = parsed.end.0 * 3600 + parsed.end.1 * 60
                if endSec <= startSec { endSec = startSec + 45 * 60 }
                grouped[WindowKey(startSec: startSec, endSec: endSec), default: []].append(item)
            }

            let slots = grouped.sorted { lhs, rhs in
                if lhs.key.startSec != rhs.key.startSec {
                    return lhs.key.startSec < rhs.key.startSec
                }
                return (lhs.value.first?.lesson.period ?? 0) < (rhs.value.first?.lesson.period ?? 0)
            }.map { (key, items) -> LiveLessonSlot in
                let first = items.first!.lesson
                let sh = key.startSec / 3600
                let sm = (key.startSec % 3600) / 60
                let eh = key.endSec / 3600
                let em = (key.endSec % 3600) / 60
                let fallback = String(format: "%d:%02d–%d:%02d", sh, sm, eh, em)
                let label = first.timeRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : first.timeRange
                return LiveLessonSlot(
                    period: first.period,
                    startSecondOfDay: key.startSec,
                    endSecondOfDay: key.endSec,
                    timeRangeLabel: label,
                    items: items
                )
            }

            return (slots, classResolution.cancelledIndices.count, classResolution.summaryBanner)
        }

        func findNextSchoolDayFirstSlot(fromDayIndex: Int?) -> (String?, LiveLessonSlot?) {
            let ordered: [Int]
            if let from = fromDayIndex {
                ordered = Array(((from + 1)...4)) + Array(0...from)
            } else {
                ordered = Array(0...4)
            }
            for dIdx in ordered {
                let built = buildSlotsForDay(dIdx, applySubs: false)
                if let first = built.slots.first {
                    let label = (fromDayIndex != nil && dIdx == fromDayIndex! + 1)
                        ? "Jutro (\(dayNames[dIdx]))"
                        : dayNames[dIdx]
                    return (label, first)
                }
            }
            return (nil, nil)
        }

        guard let todayIdx = todayDayIndex else {
            let next = findNextSchoolDayFirstSlot(fromDayIndex: nil)
            return PreparedDaySchedule(
                hasTimetable: true,
                todayDayIndex: nil,
                todayDayName: nil,
                todaySlots: [],
                cancelledCountToday: 0,
                substitutionBanner: nil,
                nextDayLabel: next.0,
                nextDayFirstSlot: next.1
            )
        }

        let builtToday = buildSlotsForDay(todayIdx, applySubs: true)
        let next = findNextSchoolDayFirstSlot(fromDayIndex: todayIdx)
        return PreparedDaySchedule(
            hasTimetable: true,
            todayDayIndex: todayIdx,
            todayDayName: todayDayName,
            todaySlots: builtToday.slots,
            cancelledCountToday: builtToday.cancelledCount,
            substitutionBanner: builtToday.banner,
            nextDayLabel: next.0,
            nextDayFirstSlot: next.1
        )
    }

    static func evaluate(prepared: PreparedDaySchedule, now: Date = Date()) -> LiveScheduleEvaluation {
        guard prepared.hasTimetable else {
            return LiveScheduleEvaluation(status: .noTimetable, todayDayIndex: nil, todayDayName: nil)
        }

        guard let todayIdx = prepared.todayDayIndex else {
            return LiveScheduleEvaluation(
                status: .weekend(nextDayLabel: prepared.nextDayLabel, nextDayFirstSlot: prepared.nextDayFirstSlot),
                todayDayIndex: nil,
                todayDayName: nil
            )
        }

        let todaySlots = prepared.todaySlots
        if todaySlots.isEmpty {
            return LiveScheduleEvaluation(
                status: .afterLessons(nextDayLabel: prepared.nextDayLabel, nextDayFirstSlot: prepared.nextDayFirstSlot),
                todayDayIndex: todayIdx,
                todayDayName: prepared.todayDayName,
                todaySlots: [],
                cancelledCountToday: prepared.cancelledCountToday,
                substitutionBanner: prepared.substitutionBanner
            )
        }

        let comps = gregorianCalendar.dateComponents([.hour, .minute, .second], from: now)
        let nowSec = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)

        if let curIdx = todaySlots.firstIndex(where: { nowSec >= $0.startSecondOfDay && nowSec < $0.endSecondOfDay }) {
            let cur = todaySlots[curIdx]
            let total = max(cur.endSecondOfDay - cur.startSecondOfDay, 1)
            let remaining = max(cur.endSecondOfDay - nowSec, 0)
            let nextSlot = curIdx + 1 < todaySlots.count ? todaySlots[curIdx + 1] : nil
            return LiveScheduleEvaluation(
                status: .duringLesson(currentSlot: cur, remainingSeconds: remaining, totalSeconds: total, nextSlot: nextSlot),
                todayDayIndex: todayIdx,
                todayDayName: prepared.todayDayName,
                todaySlots: todaySlots,
                cancelledCountToday: prepared.cancelledCountToday,
                substitutionBanner: prepared.substitutionBanner
            )
        }

        if let first = todaySlots.first, nowSec < first.startSecondOfDay {
            return LiveScheduleEvaluation(
                status: .beforeLessons(firstSlot: first, remainingSeconds: max(first.startSecondOfDay - nowSec, 0)),
                todayDayIndex: todayIdx,
                todayDayName: prepared.todayDayName,
                todaySlots: todaySlots,
                cancelledCountToday: prepared.cancelledCountToday,
                substitutionBanner: prepared.substitutionBanner
            )
        }

        if todaySlots.count > 1 {
            for i in 0..<(todaySlots.count - 1) {
                let prev = todaySlots[i]
                let next = todaySlots[i + 1]
                if nowSec >= prev.endSecondOfDay && nowSec < next.startSecondOfDay {
                    let totalBreak = max(next.startSecondOfDay - prev.endSecondOfDay, 1)
                    let remaining = max(next.startSecondOfDay - nowSec, 0)
                    return LiveScheduleEvaluation(
                        status: .breakTime(previousSlot: prev, nextSlot: next, remainingSeconds: remaining, totalSeconds: totalBreak),
                        todayDayIndex: todayIdx,
                        todayDayName: prepared.todayDayName,
                        todaySlots: todaySlots,
                        cancelledCountToday: prepared.cancelledCountToday,
                        substitutionBanner: prepared.substitutionBanner
                    )
                }
            }
        }

        return LiveScheduleEvaluation(
            status: .afterLessons(nextDayLabel: prepared.nextDayLabel, nextDayFirstSlot: prepared.nextDayFirstSlot),
            todayDayIndex: todayIdx,
            todayDayName: prepared.todayDayName,
            todaySlots: todaySlots,
            cancelledCountToday: prepared.cancelledCountToday,
            substitutionBanner: prepared.substitutionBanner
        )
    }

    static func evaluate(
        timetable: ClassTimetable?,
        substitutions: SubstitutionsSnapshot?,
        userRole: UserRole,
        selectedClassName: String,
        selectedGroup: StudentGroup,
        customGroupFilter: String,
        teacherAbbr: String,
        teacherFullName: String = "",
        hiddenSchoolIds: Set<String> = [],
        now: Date = Date()
    ) -> LiveScheduleEvaluation {
        let prepared = prepareDaySchedule(
            timetable: timetable,
            substitutions: substitutions,
            userRole: userRole,
            selectedClassName: selectedClassName,
            selectedGroup: selectedGroup,
            customGroupFilter: customGroupFilter,
            teacherAbbr: teacherAbbr,
            teacherFullName: teacherFullName,
            hiddenSchoolIds: hiddenSchoolIds,
            now: now
        )
        return evaluate(prepared: prepared, now: now)
    }

    static func formatCountdown(_ totalSeconds: Int) -> String {
        let s = max(totalSeconds, 0)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let seconds = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func formatDurationWordsPl(_ totalSeconds: Int) -> String {
        let s = max(totalSeconds, 0)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours) godz. \(minutes) min"
        } else if hours > 0 {
            return "\(hours) godz."
        } else if minutes > 0 {
            return "\(minutes) min"
        }
        return "\(s) sek."
    }
}
