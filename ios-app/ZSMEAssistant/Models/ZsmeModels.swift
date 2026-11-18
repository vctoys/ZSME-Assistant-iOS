import Foundation

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case student = "STUDENT"
    case teacher = "TEACHER"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .student: return "Uczeń"
        case .teacher: return "Nauczyciel"
        }
    }
}

enum TimetableCategory: String, Codable, CaseIterable, Identifiable {
    case schoolClass = "CLASS"
    case teacher = "TEACHER"
    case room = "ROOM"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .schoolClass: return "Klasy"
        case .teacher: return "Nauczyciele"
        case .room: return "Sale"
        }
    }
}

struct SchoolClass: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
}

struct TimetableTarget: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let category: TimetableCategory
}

struct TimetableCatalog: Codable {
    var classes: [SchoolClass] = []
    var teachers: [TimetableTarget] = []
    var rooms: [TimetableTarget] = []
}

enum StudentGroup: String, Codable, CaseIterable, Identifiable {
    case all = "ALL"
    case group1 = "GROUP_1"
    case group2 = "GROUP_2"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "Wszystkie grupy (cała klasa)"
        case .group1: return "Grupa 1 (1/2)"
        case .group2: return "Grupa 2 (2/2)"
        }
    }

    var shortLabel: String {
        switch self {
        case .all: return "Cała klasa"
        case .group1: return "Grupa 1"
        case .group2: return "Grupa 2"
        }
    }
}

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Systemowy"
        case .light: return "Jasny"
        case .dark: return "Ciemny"
        }
    }
}

struct TeacherSchoolConfig: Codable, Identifiable, Hashable {
    var id: String
    var schoolName: String
    var teacherAbbreviation: String
    var planUrl: String
    var colorIndex: Int = 0
}

struct LessonEntry: Codable, Identifiable, Hashable {
    var id: String {
        "\(schoolId)_\(period)_\(subject)_\(teacher)_\(room)_\(groupTag ?? "")_\(classGroupLabel)"
    }
    let period: Int
    let timeRange: String
    let subject: String
    var teacher: String
    let room: String
    var classGroupLabel: String = ""
    var groupTag: String? = nil
    var rawText: String = ""
    var schoolId: String = ""
    var schoolName: String = ""
    var schoolColorIndex: Int = -1
}

struct DaySchedule: Codable, Identifiable, Hashable {
    var id: Int { dayIndex }
    let dayIndex: Int // 0 = Poniedziałek .. 4 = Piątek
    let dayName: String
    var lessons: [LessonEntry]
}

struct ClassTimetable: Codable, Hashable {
    var className: String
    var classUrl: String
    var category: TimetableCategory = .schoolClass
    var generatedInfo: String = ""
    var days: [DaySchedule] = []
    var fetchedAtMillis: Int64 = 0
    var contentHash: String = ""
}

struct SubstitutionItem: Codable, Identifiable, Hashable {
    let id: String
    var dateLabel: String = ""
    var className: String = ""
    var period: String = ""
    var timeRange: String = ""
    var absentTeacher: String = ""
    var subject: String = ""
    var substituteTeacher: String = ""
    var room: String = ""
    var note: String = ""
    var groupTag: String? = nil
    var isCancellation: Bool = false
}

struct SubstitutionsSnapshot: Codable, Hashable {
    var dateHeading: String = ""
    var items: [SubstitutionItem] = []
    var announcements: [String] = []
    var notes: [String] = []
    var fetchedAtMillis: Int64 = 0
    var rawHash: String = ""
    var authSucceeded: Bool = true
    var sourceUrl: String = ""
}

struct NotificationLogEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let timestampMillis: Int64
    let category: String // "SUBSTITUTION" or "TIMETABLE"
}

struct UserPreferences: Codable, Equatable {
    static let primarySchoolId = "primary_zsme"
    static let defaultSecretariatKey = "zsmeedukacja"
    static let teacherAccessPassword = "zsmeedukacja"
    static let defaultPlanUrl = "https://plan.zsme.pl/"
    static let defaultSubstitutionsUrl = "https://sekretariat.zsme.pl/tv.php"

    var userRole: UserRole = .student
    var teacherAbbreviation: String = ""
    var teacherFullName: String = ""
    var selectedClassId: String = ""
    var selectedClassName: String = ""
    var selectedClassUrl: String = ""
    var selectedGroup: StudentGroup = .all
    var customGroupFilter: String = ""
    var substitutionsUrl: String = defaultSubstitutionsUrl
    var planUrl: String = defaultPlanUrl
    var secretariatKey: String = defaultSecretariatKey
    var notificationsEnabled: Bool = true
    var checkIntervalMinutes: Int = 15
    var lastNotifiedSubstitutionsHash: String = ""
    var lastNotifiedTimetableHash: String = ""
    var themeMode: ThemeMode = .system
    var recentNotifications: [NotificationLogEntry] = []
    var meshNickname: String = ""
    var additionalSchools: [TeacherSchoolConfig] = []

    static func isValidTeacherAccessPassword(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == teacherAccessPassword
    }

    static func deriveSchoolLabel(url: String, fallback: String = "Szkoła") -> String {
        guard let host = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.host else {
            return fallback
        }
        let cleaned = host
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "plan.", with: "")
        if cleaned.localizedCaseInsensitiveContains("zsme") {
            return "ZSME"
        }
        let first = cleaned.split(separator: ".").first.map(String.init) ?? ""
        return first.isEmpty ? fallback : first.uppercased()
    }

    func allTeacherSchools() -> [TeacherSchoolConfig] {
        var list: [TeacherSchoolConfig] = []
        let abbr = teacherAbbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !abbr.isEmpty {
            let cleanPlan = planUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectivePlan = cleanPlan.isEmpty ? Self.defaultPlanUrl : cleanPlan
            list.append(
                TeacherSchoolConfig(
                    id: Self.primarySchoolId,
                    schoolName: Self.deriveSchoolLabel(url: effectivePlan, fallback: "ZSME"),
                    teacherAbbreviation: abbr.uppercased(),
                    planUrl: effectivePlan,
                    colorIndex: 0
                )
            )
        }
        for (idx, school) in additionalSchools.enumerated() {
            let sAbbr = school.teacherAbbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
            let sUrl = school.planUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sAbbr.isEmpty && !sUrl.isEmpty {
                let sName = school.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = sName.isEmpty ? Self.deriveSchoolLabel(url: sUrl, fallback: "Szkoła \(idx + 2)") : sName
                list.append(
                    TeacherSchoolConfig(
                        id: school.id,
                        schoolName: label,
                        teacherAbbreviation: sAbbr.uppercased(),
                        planUrl: sUrl,
                        colorIndex: school.colorIndex > 0 ? school.colorIndex : (idx + 1)
                    )
                )
            }
        }
        return list
    }
}

enum TeacherSubstitutionMatch {
    case none
    case conducting
    case replaced
}

struct ClassDaySubstitutionResolution {
    var byLessonIndex: [Int: SubstitutionItem] = [:]
    var cancelledIndices: Set<Int> = []
    var comesLater: Bool = false
    var endsEarlier: Bool = false
    var summaryBanner: String? = nil
}

enum ScheduleFilterMatcher {
    private static let group1Markers = ["1/2", "gr.1", "gr. 1", "gr 1", "grupa 1", "-1/2", "/1", "(1)", "g1", "gr1"]
    private static let group2Markers = ["2/2", "gr.2", "gr. 2", "gr 2", "grupa 2", "-2/2", "/2", "(2)", "g2", "gr2"]
    private static let classSpaceRegex = try? NSRegularExpression(pattern: "(\\d)\\s+([A-ZĄĆĘŁŃÓŚŹŻ])")
    private static let periodRangeRegex = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*[-–]\\s*(\\d{1,2})")
    private static let timeStripRegex = try? NSRegularExpression(pattern: "\\d{1,2}:\\d{2}")
    private static let periodNumberRegex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})\\b")
    private static let gregorianCalendar = Calendar(identifier: .gregorian)

    static func foldPolishDiacritics(_ text: String) -> String {
        let map: [Character: Character] = [
            "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
            "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z"
        ]
        return String(text.map { map[$0] ?? $0 })
    }

    static func detectGroupTag(_ text: String) -> String? {
        let lower = text.lowercased()
        if group1Markers.contains(where: { containsToken(lower, marker: $0) }) { return "1/2" }
        if group2Markers.contains(where: { containsToken(lower, marker: $0) }) { return "2/2" }
        return nil
    }

    private static func containsToken(_ lowerText: String, marker: String) -> Bool {
        if marker == "/1" || marker == "/2" {
            let escaped = NSRegularExpression.escapedPattern(for: marker)
            let pattern = "(?<!\\d)\(escaped)(?!\\d)"
            return lowerText.range(of: pattern, options: .regularExpression) != nil
        }
        return lowerText.contains(marker)
    }

    static func matchesGroup(
        groupTag: String?,
        combinedText: String,
        selectedGroup: StudentGroup,
        customGroupFilter: String
    ) -> Bool {
        let detected = groupTag ?? detectGroupTag(combinedText)
        let groupMatches: Bool
        switch selectedGroup {
        case .all:
            groupMatches = true
        case .group1:
            groupMatches = detected == nil || detected == "1/2"
        case .group2:
            groupMatches = detected == nil || detected == "2/2"
        }
        if !groupMatches { return false }

        let custom = customGroupFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !custom.isEmpty && detected != nil {
            let lower = combinedText.lowercased()
            if lower.contains("gr.") || lower.contains("grupa") || lower.contains("/2") {
                return lower.contains(custom) || !looksLikeSpecificElective(lower)
            }
        }
        return true
    }

    private static func looksLikeSpecificElective(_ lower: String) -> Bool {
        ["ang", "niem", "inf", "wf", "rel", "dz", "ch"].contains { lower.contains($0) }
    }

    static func normalizeClassToken(_ raw: String) -> String {
        var upper = raw.uppercased()
            .replacingOccurrences(of: "KLASA", with: "")
            .replacingOccurrences(of: "KL.", with: "")
        if let regex = classSpaceRegex {
            let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
            upper = regex.stringByReplacingMatches(in: upper, options: [], range: range, withTemplate: "$1$2")
        }
        return upper.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractPrimaryClassCode(_ raw: String) -> String {
        let norm = normalizeClassToken(raw)
        let pattern = "\\b([1-6][A-ZĄĆĘŁŃÓŚŹŻ]{1,5}\\d?)\\b"
        if let range = norm.range(of: pattern, options: .regularExpression) {
            return String(norm[range])
        }
        return norm
    }

    static func matchesClass(
        selectedClassName: String,
        itemClassName: String,
        fallbackText: String = ""
    ) -> Bool {
        let target = extractPrimaryClassCode(selectedClassName)
        if target.isEmpty { return false }
        let escaped = NSRegularExpression.escapedPattern(for: target)
        let pattern = "(?<![A-Z0-9])\(escaped)(?![A-Z])"
        let candidate = normalizeClassToken(itemClassName)
        if !candidate.isEmpty && candidate.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        let fallback = normalizeClassToken(fallbackText)
        if !fallback.isEmpty && fallback.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func matchesSubstitution(
        item: SubstitutionItem,
        selectedClassName: String,
        selectedGroup: StudentGroup,
        customGroupFilter: String
    ) -> Bool {
        if selectedClassName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let combined = [item.className, item.subject, item.note, item.groupTag ?? ""].joined(separator: " ")
        if !matchesClass(selectedClassName: selectedClassName, itemClassName: item.className, fallbackText: combined) {
            return false
        }
        return matchesGroup(
            groupTag: item.groupTag,
            combinedText: combined,
            selectedGroup: selectedGroup,
            customGroupFilter: customGroupFilter
        )
    }

    static func matchesTeacherToken(_ text: String, teacherAbbr: String) -> Bool {
        let cleanAbbr = teacherAbbr.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAbbr.isEmpty || text.isEmpty { return false }
        let escaped = NSRegularExpression.escapedPattern(for: cleanAbbr)
        let boundary = "[A-ZĄĆĘŁŃÓŚŹŻa-ząćęłńóśźż0-9]"
        let exactPattern = "(?<!\(boundary))\(escaped)(?!\(boundary))"
        if text.range(of: exactPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let lettersOnly = cleanAbbr.filter { $0.isLetter }
        if (2...4).contains(lettersOnly.count) {
            let dotted = lettersOnly.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\.?\\s*") + "\\.?"
            let dottedPattern = "(?<!\(boundary))\(dotted)(?!\(boundary))"
            if text.range(of: dottedPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    static func matchesTeacherSubstitution(
        item: SubstitutionItem,
        teacherAbbr: String,
        teacherFullName: String = ""
    ) -> TeacherSubstitutionMatch {
        let keys = [teacherAbbr.trimmingCharacters(in: .whitespacesAndNewlines), teacherFullName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
        if keys.isEmpty { return .none }
        let subText = "\(item.substituteTeacher) \(item.note)"
        if keys.contains(where: { matchesTeacherToken(subText, teacherAbbr: $0) }) {
            return .conducting
        }
        if keys.contains(where: { matchesTeacherToken(item.absentTeacher, teacherAbbr: $0) }) {
            return .replaced
        }
        return .none
    }

    static func isCancellationText(_ text: String) -> Bool {
        let folded = foldPolishDiacritics(text).lowercased()
        let keywords = [
            "odwolan", "zwolnion", "do domu", "przychodzi pozniej", "przychodza pozniej",
            "konczy szybciej", "koncza szybciej", "konczy wczesniej", "koncza wczesniej",
            "brak zajec", "nie ma lekcji", "lekcja odwolana", "zajecia odwolane"
        ]
        return keywords.contains { folded.contains($0) }
    }

    static func isDutyText(_ text: String) -> Bool {
        let folded = foldPolishDiacritics(text).lowercased()
        return folded.contains("dyzur") || folded.contains("przerwa") || folded.contains("po lekcji")
    }

    static func parseSubstitutionPeriods(_ rawPeriod: String) -> Set<Int> {
        let clean = rawPeriod.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return [] }
        var result: Set<Int> = []

        if let rangeRegex = periodRangeRegex {
            let nsRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            for match in rangeRegex.matches(in: clean, options: [], range: nsRange) {
                if let r1 = Range(match.range(at: 1), in: clean),
                   let r2 = Range(match.range(at: 2), in: clean),
                   let start = Int(clean[r1]),
                   let end = Int(clean[r2]),
                   start <= end, end - start <= 12 {
                    for p in start...end where (0...16).contains(p) {
                        result.insert(p)
                    }
                }
            }
        }

        var stripped = clean
        if let timeRegex = timeStripRegex {
            let nsRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            stripped = timeRegex.stringByReplacingMatches(in: stripped, options: [], range: nsRange, withTemplate: " ")
        }
        if let numRegex = periodNumberRegex {
            let nsRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            for match in numRegex.matches(in: stripped, options: [], range: nsRange) {
                if let r = Range(match.range(at: 1), in: stripped), let num = Int(stripped[r]), (0...16).contains(num) {
                    result.insert(num)
                }
            }
        }
        return result
    }

    static func substitutionAppliesToDay(
        dateLabel: String,
        fallbackDateHeading: String,
        dayIndex: Int,
        todayWeekdayIndex: Int?
    ) -> Bool {
        let raw = (dateLabel.isEmpty ? fallbackDateHeading : dateLabel).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return todayWeekdayIndex == nil || dayIndex == todayWeekdayIndex
        }
        let folded = foldPolishDiacritics(raw).lowercased()
        let weekdayTokens: [(Int, [String])] = [
            (0, ["poniedzialek", "pon.", " pn"]),
            (1, ["wtorek", "wt.", " wt"]),
            (2, ["sroda", "sr.", " sr"]),
            (3, ["czwartek", "czw.", " cz"]),
            (4, ["piatek", "pt.", " pt"])
        ]
        for (idx, tokens) in weekdayTokens {
            if tokens.contains(where: { folded.contains($0) }) {
                return idx == dayIndex
            }
        }
        // Fallback numeric date check dd.MM.yyyy or yyyy-MM-dd
        let cal = gregorianCalendar
        if let dateMatch = raw.range(of: "\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) {
            let parts = raw[dateMatch].split(separator: "-").compactMap { Int($0) }
            if parts.count == 3,
               let parsedDate = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
                let wd = cal.component(.weekday, from: parsedDate)
                return weekdayToZeroBasedIndex(wd) == dayIndex
            }
        }
        if let dateMatch = raw.range(of: "\\d{2}\\.\\d{2}\\.\\d{4}", options: .regularExpression) {
            let parts = raw[dateMatch].split(separator: ".").compactMap { Int($0) }
            if parts.count == 3,
               let parsedDate = cal.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0])) {
                let wd = cal.component(.weekday, from: parsedDate)
                return weekdayToZeroBasedIndex(wd) == dayIndex
            }
        }
        return todayWeekdayIndex == nil || dayIndex == todayWeekdayIndex
    }

    static func weekdayToZeroBasedIndex(_ calendarWeekday: Int) -> Int? {
        switch calendarWeekday {
        case 2: return 0 // Monday
        case 3: return 1
        case 4: return 2
        case 5: return 3
        case 6: return 4 // Friday
        default: return nil
        }
    }

    static func resolveClassDaySubstitutions(
        dayLessons: [LessonEntry],
        dayIndex: Int,
        todayWeekdayIndex: Int?,
        snapshot: SubstitutionsSnapshot?,
        className: String,
        selectedGroup: StudentGroup,
        customGroupFilter: String
    ) -> ClassDaySubstitutionResolution {
        guard let snapshot = snapshot, !dayLessons.isEmpty, !className.isEmpty else {
            return ClassDaySubstitutionResolution()
        }
        let matchingItems = snapshot.items.filter { item in
            matchesSubstitution(
                item: item,
                selectedClassName: className,
                selectedGroup: selectedGroup,
                customGroupFilter: customGroupFilter
            ) && substitutionAppliesToDay(
                dateLabel: item.dateLabel,
                fallbackDateHeading: snapshot.dateHeading,
                dayIndex: dayIndex,
                todayWeekdayIndex: todayWeekdayIndex
            )
        }
        if matchingItems.isEmpty {
            return ClassDaySubstitutionResolution()
        }

        var resolvedByIndex: [Int: SubstitutionItem] = [:]
        for item in matchingItems {
            let periods = parseSubstitutionPeriods(item.period)
            let itemText = [item.subject, item.substituteTeacher, item.note]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            let effectiveCancel = item.isCancellation || isCancellationText(itemText)

            for (idx, lesson) in dayLessons.enumerated() where periods.contains(lesson.period) {
                let subGroup = item.groupTag ?? detectGroupTag("\(item.className) \(item.subject) \(item.note)")
                let lessonGroup = lesson.groupTag ?? detectGroupTag("\(lesson.subject) \(lesson.rawText)")
                if let sg = subGroup, let lg = lessonGroup, sg != lg {
                    continue
                }
                var updated = item
                if effectiveCancel { updated.isCancellation = true }
                if resolvedByIndex[idx] == nil || (!resolvedByIndex[idx]!.isCancellation && updated.isCancellation) {
                    resolvedByIndex[idx] = updated
                }
            }
        }

        if resolvedByIndex.isEmpty {
            return ClassDaySubstitutionResolution()
        }

        let cancelledIndices = Set(resolvedByIndex.filter { $0.value.isCancellation }.map { $0.key })
        let activeSubCount = resolvedByIndex.values.filter { !$0.isCancellation }.count
        let remaining = dayLessons.enumerated().filter { !cancelledIndices.contains($0.offset) }.map { $0.element }
        let firstPeriod = dayLessons.map(\.period).min() ?? 0
        let lastPeriod = dayLessons.map(\.period).max() ?? 0
        let comesLater = !cancelledIndices.isEmpty && !remaining.isEmpty && (remaining.first?.period ?? 0) > firstPeriod
        let endsEarlier = !cancelledIndices.isEmpty && !remaining.isEmpty && (remaining.last?.period ?? 0) < lastPeriod
        let allCancelled = !cancelledIndices.isEmpty && remaining.isEmpty

        var parts: [String] = []
        if allCancelled {
            parts.append("Wszystkie lekcje odwołane (\(cancelledIndices.count))")
        } else if comesLater && endsEarlier, let first = remaining.first, let last = remaining.last {
            parts.append("Klasa przychodzi później (od \(first.period) lek.) i kończy szybciej (po \(last.period) lek.)")
        } else if comesLater, let first = remaining.first {
            parts.append("Klasa przychodzi później • początek od \(first.period) lek.")
        } else if endsEarlier, let last = remaining.last {
            parts.append("Klasa kończy szybciej • koniec po \(last.period) lek.")
        } else if !cancelledIndices.isEmpty {
            parts.append("Odwołane lekcje: \(cancelledIndices.count)")
        }
        if activeSubCount > 0 {
            parts.append("Zastępstwa: \(activeSubCount)")
        }

        return ClassDaySubstitutionResolution(
            byLessonIndex: resolvedByIndex,
            cancelledIndices: cancelledIndices,
            comesLater: comesLater,
            endsEarlier: endsEarlier,
            summaryBanner: parts.isEmpty ? nil : parts.joined(separator: " • ")
        )
    }

    static func filterLessonsByVisibleSchools(
        _ lessons: [LessonEntry],
        hiddenSchoolIds: Set<String>,
        fallbackSchoolId: String = UserPreferences.primarySchoolId
    ) -> [LessonEntry] {
        guard !hiddenSchoolIds.isEmpty else { return lessons }
        return lessons.filter { lesson in
            let effective = lesson.schoolId.isEmpty ? fallbackSchoolId : lesson.schoolId
            return !hiddenSchoolIds.contains(effective)
        }
    }
}
