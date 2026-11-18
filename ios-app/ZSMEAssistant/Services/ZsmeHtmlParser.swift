import Foundation
import CryptoKit
import SwiftSoup

struct AuthFormPayload {
    let actionUrl: String
    let method: String
    let fields: [String: String]
}

enum ZsmeHtmlParser {
    static let defaultDays = ["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek"]

    static func extractFrameUrls(html: String, baseUrl: String) -> [String] {
        guard let doc = try? SwiftSoup.parse(html, baseUrl) else { return [] }
        var urls: [String] = []
        if let frames = try? doc.select("frame[src], iframe[src]") {
            for el in frames {
                let src = (try? el.attr("src"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !src.isEmpty {
                    let resolved = resolveUrl(baseUrl: baseUrl, relative: src)
                    if !resolved.isEmpty && resolved != baseUrl && !urls.contains(resolved) {
                        urls.append(resolved)
                    }
                }
            }
        }
        if let metas = try? doc.select("meta[http-equiv=refresh]") {
            for el in metas {
                let content = (try? el.attr("content")) ?? ""
                if let range = content.range(of: "url=", options: .caseInsensitive) {
                    let raw = String(content[range.upperBound...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
                    let resolved = resolveUrl(baseUrl: baseUrl, relative: raw)
                    if !resolved.isEmpty && !urls.contains(resolved) {
                        urls.append(resolved)
                    }
                }
            }
        }
        return urls
    }

    static func extractCatalogSubpageUrls(html: String, baseUrl: String) -> [String] {
        guard let doc = try? SwiftSoup.parse(html, baseUrl) else { return [] }
        var urls: [String] = []
        guard let links = try? doc.select("a[href]") else { return [] }
        for a in links {
            let href = (try? a.attr("href"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lower = href.lowercased()
            let text = ((try? a.text()) ?? "").lowercased()
            if href.isEmpty || lower.hasPrefix("javascript:") || lower.hasPrefix("#") { continue }
            let keywords = ["lista", "menu", "spis", "nauczyc", "sale", "oddz", "plany"]
            if keywords.contains(where: { lower.contains($0) || text.contains($0) }) {
                let abs = resolveUrl(baseUrl: baseUrl, relative: href)
                if !abs.isEmpty && abs != baseUrl && !urls.contains(abs) {
                    urls.append(abs)
                }
            }
        }
        return urls
    }

    static func parseTimetableCatalog(html: String, baseUrl: String) -> TimetableCatalog {
        guard let doc = try? SwiftSoup.parse(html, baseUrl) else {
            return TimetableCatalog()
        }
        var classes: [String: SchoolClass] = [:]
        var teachers: [String: TimetableTarget] = [:]
        var rooms: [String: TimetableTarget] = [:]

        let ignored = Set([
            "index.html", "index.htm", "index.php", "lista.html", "lista.htm",
            "menu.html", "menu.htm", "szablon.html", "pomoc.html", "help.html"
        ])

        func classify(href: String, cssClass: String) -> TimetableCategory? {
            let cleanPath = href.split(separator: "?").first.map(String.init)?.lowercased() ?? href.lowercased()
            let fileName = cleanPath.split(separator: "/").last.map(String.init) ?? cleanPath
            if ignored.contains(fileName) { return nil }
            let clsTokens = cssClass.lowercased().split(separator: " ").map(String.init)

            if clsTokens.contains("o") ||
               cleanPath.range(of: "(^|.*/)o\\d+[^/]*\\.html?$", options: .regularExpression) != nil ||
               cleanPath.contains("plany/o") {
                return .schoolClass
            }
            if clsTokens.contains("n") ||
               cleanPath.range(of: "(^|.*/)n\\d+[^/]*\\.html?$", options: .regularExpression) != nil ||
               cleanPath.contains("plany/n") {
                return .teacher
            }
            if clsTokens.contains("s") ||
               cleanPath.range(of: "(^|.*/)s\\d+[^/]*\\.html?$", options: .regularExpression) != nil ||
               cleanPath.contains("plany/s") {
                return .room
            }
            return nil
        }

        if let links = try? doc.select("a[href]") {
            for a in links {
                let rawHref = (try? a.attr("href"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let cssClass = (try? a.className()) ?? ""
                if rawHref.isEmpty || text.isEmpty || rawHref.hasPrefix("javascript:") || rawHref.hasPrefix("#") {
                    continue
                }
                guard let category = classify(href: rawHref, cssClass: cssClass) else { continue }
                let absUrl = resolveUrl(baseUrl: baseUrl, relative: rawHref)
                let id = absUrl.split(separator: "/").last.map(String.init) ?? absUrl
                switch category {
                case .schoolClass:
                    classes[absUrl] = classes[absUrl] ?? SchoolClass(id: id, name: text, url: absUrl)
                case .teacher:
                    teachers[absUrl] = teachers[absUrl] ?? TimetableTarget(id: id, name: text, url: absUrl, category: .teacher)
                case .room:
                    rooms[absUrl] = rooms[absUrl] ?? TimetableTarget(id: id, name: text, url: absUrl, category: .room)
                }
            }
        }

        let sortedClasses = classes.values.sorted { a, b in
            let na = Int(a.name.prefix(while: \.isNumber)) ?? 99
            let nb = Int(b.name.prefix(while: \.isNumber)) ?? 99
            if na != nb { return na < nb }
            return a.name < b.name
        }
        let sortedTeachers = teachers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sortedRooms = rooms.values.sorted { a, b in
            let na = Int(a.name.prefix(while: \.isNumber)) ?? Int.max
            let nb = Int(b.name.prefix(while: \.isNumber)) ?? Int.max
            if na != nb { return na < nb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return TimetableCatalog(classes: sortedClasses, teachers: sortedTeachers, rooms: sortedRooms)
    }

    static func hasTimetableStructure(html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        if (try? doc.select("table.tabela").first()) != nil { return true }
        if let tables = try? doc.select("table") {
            for t in tables {
                let rows = (try? t.select("tr").size()) ?? 0
                if rows >= 3 { return true }
            }
        }
        return false
    }

    static func parseTimetable(
        html: String,
        className: String,
        classUrl: String,
        category: TimetableCategory = .schoolClass
    ) -> ClassTimetable {
        guard let doc = try? SwiftSoup.parse(html, classUrl),
              let table = (try? doc.select("table.tabela").first()) ??
                          (try? doc.select("table").array().max(by: { ((try? $0.select("tr").size()) ?? 0) < ((try? $1.select("tr").size()) ?? 0) }))
        else {
            return ClassTimetable(
                className: className,
                classUrl: classUrl,
                category: category,
                days: defaultDays.enumerated().map { DaySchedule(dayIndex: $0.offset, dayName: $0.element, lessons: []) },
                fetchedAtMillis: Int64(Date().timeIntervalSince1970 * 1000)
            )
        }

        let rows = (try? table.select("tr").array()) ?? []
        if rows.isEmpty {
            return ClassTimetable(className: className, classUrl: classUrl, category: category)
        }

        struct GridSlot {
            let element: Element
            let isColSpanContinuation: Bool
        }
        var grid = [[GridSlot?]](repeating: [], count: rows.count)

        for (rIdx, tr) in rows.enumerated() {
            let cells = tr.children().array().filter {
                let tag = $0.tagName().lowercased()
                return tag == "th" || tag == "td"
            }
            var cIdx = 0
            for cell in cells {
                while cIdx < grid[rIdx].count && grid[rIdx][cIdx] != nil {
                    cIdx += 1
                }
                let rowspan = max(Int((try? cell.attr("rowspan")) ?? "1") ?? 1, 1)
                let colspan = max(Int((try? cell.attr("colspan")) ?? "1") ?? 1, 1)
                for dr in 0..<rowspan {
                    let trRow = rIdx + dr
                    if trRow >= rows.count { break }
                    while grid[trRow].count < cIdx + colspan {
                        grid[trRow].append(nil)
                    }
                    for dc in 0..<colspan {
                        grid[trRow][cIdx + dc] = GridSlot(element: cell, isColSpanContinuation: dc > 0)
                    }
                }
                cIdx += colspan
            }
        }

        let headerRow = grid.first ?? []
        let dayColStart = headerRow.count >= 7 ? 2 : (headerRow.count == 6 ? 1 : 2)
        var lessonsByDay = [[LessonEntry]](repeating: [], count: 5)

        for rIdx in 1..<grid.count {
            let row = grid[rIdx]
            guard row.count > dayColStart else { continue }
            let periodText = ((try? row[0]?.element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let periodNum = Int(periodText.filter(\.isNumber)) ?? (rIdx - 1)
            let timeRange = dayColStart > 1
                ? (((try? row[1]?.element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                : ""

            for dIdx in 0..<5 {
                let colIdx = dayColStart + dIdx
                guard colIdx < row.count, let slot = row[colIdx], !slot.isColSpanContinuation else { continue }
                let entries = parseLessonCell(slot.element, periodNum: periodNum, timeRange: timeRange, baseUrl: classUrl)
                lessonsByDay[dIdx].append(contentsOf: entries)
            }
        }

        let days = defaultDays.enumerated().map { idx, name in
            DaySchedule(
                dayIndex: idx,
                dayName: name,
                lessons: lessonsByDay[idx].sorted { $0.period < $1.period }
            )
        }

        let hashSource = days.map { d in
            "\(d.dayName):" + d.lessons.map { "\($0.period):\($0.subject):\($0.teacher):\($0.room):\($0.groupTag ?? "")" }.joined(separator: ";")
        }.joined(separator: "|")

        let generatedInfo = ((try? doc.select("td.op, .tytulnapis").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ClassTimetable(
            className: className,
            classUrl: classUrl,
            category: category,
            generatedInfo: generatedInfo,
            days: days,
            fetchedAtMillis: Int64(Date().timeIntervalSince1970 * 1000),
            contentHash: sha256(hashSource)
        )
    }

    private static func parseLessonCell(_ cell: Element, periodNum: Int, timeRange: String, baseUrl: String) -> [LessonEntry] {
        let cellText = ((try? cell.text()) ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cellText.isEmpty || cellText == "-" || cellText == "—" { return [] }

        let rawHtml = (try? cell.html()) ?? ""
        let brNormalized = rawHtml
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<hr\\s*/?>", with: "\n", options: .regularExpression)
        let lines = brNormalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let segments = lines.isEmpty ? [rawHtml] : lines

        var entries: [LessonEntry] = []
        for segHtml in segments {
            guard let segDoc = try? SwiftSoup.parseBodyFragment(segHtml, baseUrl) else { continue }
            let segText = ((try? segDoc.text()) ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if segText.isEmpty || segText == "-" || segText == "—" { continue }

            let teachers = ((try? segDoc.select("a.n, span.n, .n").array()) ?? [])
                .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let rooms = ((try? segDoc.select("a.s, span.s, .s").array()) ?? [])
                .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let classes = ((try? segDoc.select("a.o, span.o, .o").array()) ?? [])
                .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let subjects = ((try? segDoc.select("span.p, .p").array()) ?? [])
                .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let teacherStr = Array(NSOrderedSet(array: teachers)) as? [String] ?? teachers
            let roomStr = Array(NSOrderedSet(array: rooms)) as? [String] ?? rooms
            let classStr = Array(NSOrderedSet(array: classes)) as? [String] ?? classes

            let subject = subjects.isEmpty ? segText : subjects.joined(separator: " ")
            let classGroupLabel = classStr.joined(separator: ", ")
            let groupTag = ScheduleFilterMatcher.detectGroupTag("\(subject) \(classGroupLabel) \(segText)")

            entries.append(
                LessonEntry(
                    period: periodNum,
                    timeRange: timeRange,
                    subject: subject,
                    teacher: teacherStr.joined(separator: ", "),
                    room: roomStr.joined(separator: ", "),
                    classGroupLabel: classGroupLabel,
                    groupTag: groupTag,
                    rawText: segText
                )
            )
        }
        return entries
    }

    static func detectAuthForm(html: String, currentUrl: String, accessKey: String) -> AuthFormPayload? {
        guard let doc = try? SwiftSoup.parse(html, currentUrl),
              let forms = try? doc.select("form") else { return nil }
        let keyWords = ["klucz", "key", "haslo", "hasło", "pass", "password", "kod", "code", "pin", "token", "access"]

        for form in forms {
            let inputs = (try? form.select("input").array()) ?? []
            let passwordInput = inputs.first { ((try? $0.attr("type")) ?? "").lowercased() == "password" }
            let keyInput = inputs.first { input in
                let name = ((try? input.attr("name")) ?? "").lowercased()
                let placeholder = ((try? input.attr("placeholder")) ?? "").lowercased()
                let id = ((try? input.attr("id")) ?? "").lowercased()
                return keyWords.contains { name.contains($0) || placeholder.contains($0) || id.contains($0) }
            }
            guard let target = passwordInput ?? keyInput else { continue }
            var fields: [String: String] = [:]
            for input in inputs {
                let name = ((try? input.attr("name")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { continue }
                let type = ((try? input.attr("type")) ?? "").lowercased()
                if type == "checkbox" || type == "radio" {
                    if input.hasAttr("checked") {
                        let val = (try? input.attr("value")) ?? ""
                        fields[name] = val.isEmpty ? "on" : val
                    }
                } else {
                    fields[name] = (try? input.attr("value")) ?? ""
                }
            }
            let targetName = ((try? target.attr("name")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !targetName.isEmpty {
                fields[targetName] = accessKey
            }
            let rawAction = ((try? form.attr("action")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let actionUrl = rawAction.isEmpty ? currentUrl : resolveUrl(baseUrl: currentUrl, relative: rawAction)
            let method = ((try? form.attr("method")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return AuthFormPayload(actionUrl: actionUrl, method: method.isEmpty ? "POST" : method, fields: fields)
        }
        return nil
    }

    static func findSubstitutionSubpageUrl(html: String, currentUrl: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html, currentUrl),
              let links = try? doc.select("a[href]") else { return nil }
        for a in links {
            let text = ((try? a.text()) ?? "").lowercased()
            let href = ((try? a.attr("href")) ?? "").lowercased()
            if href.hasPrefix("javascript:") || href.hasPrefix("#") { continue }
            if text.contains("zastępstw") || text.contains("zastepstw") || href.contains("zastepstw") || href.contains("tv.php") {
                let rawHref = (try? a.attr("href")) ?? ""
                let abs = resolveUrl(baseUrl: currentUrl, relative: rawHref)
                if !abs.isEmpty && abs != currentUrl { return abs }
            }
        }
        return nil
    }

    static func parseSubstitutions(html: String, sourceUrl: String) -> SubstitutionsSnapshot {
        guard let doc = try? SwiftSoup.parse(html, sourceUrl) else {
            return SubstitutionsSnapshot(sourceUrl: sourceUrl)
        }
        _ = try? doc.select("script, style, noscript, svg").remove()

        let headingEl = try? doc.select(".naglowek, h1, h2, h3").first()
        let dateHeading = ((try? headingEl?.text()) ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var items: [SubstitutionItem] = []
        var announcements: [String] = []
        var notes: [String] = []

        // Parse Informacje / Uwagi fieldsets (like sekretariat.zsme.pl/tv.php)
        if let fieldsets = try? doc.select("fieldset") {
            for fs in fieldsets {
                let legend = ((try? fs.select("legend").text()) ?? "").lowercased()
                let fsHtml = (try? fs.outerHtml()) ?? ""
                let rawHtml: String
                if let copyDoc = try? SwiftSoup.parseBodyFragment(fsHtml, sourceUrl),
                   let body = copyDoc.body() {
                    _ = try? body.select("legend").remove()
                    rawHtml = (try? body.select("fieldset").first()?.html()) ?? ((try? body.html()) ?? "")
                } else {
                    rawHtml = (try? fs.html()) ?? ""
                }
                let lines = rawHtml
                    .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: String.CompareOptions.regularExpression)
                    .components(separatedBy: "\n")
                    .compactMap { line -> String? in
                        let txt = (try? SwiftSoup.parseBodyFragment(line).text())?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return txt.isEmpty ? nil : txt
                    }
                if legend.contains("uwag") {
                    notes.append(contentsOf: lines)
                } else {
                    announcements.append(contentsOf: lines)
                }
            }
        }

        // Parse substitution tables
        if let tables = try? doc.select("table") {
            for table in tables {
                let rows = (try? table.select("tr").array()) ?? []
                if rows.isEmpty { continue }

                var colPeriod = -1
                var colAbsent = -1
                var colClass = -1
                var colSubject = -1
                var colRoom = -1
                var colSub = -1
                var colNote = -1
                var currentDate = dateHeading
                var startRow = 0

                for (idx, tr) in rows.enumerated() {
                    let ths = tr.children().array().filter { $0.tagName().lowercased() == "th" }
                    let tds = tr.children().array().filter { $0.tagName().lowercased() == "td" }
                    let cells = !ths.isEmpty ? ths : tds
                    let texts = cells.map { ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

                    if texts.count == 1, let single = texts.first, !single.isEmpty {
                        if single.localizedCaseInsensitiveContains("Dzień:") ||
                           single.range(of: "\\d{2}\\.\\d{2}\\.\\d{4}|\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil {
                            currentDate = single.replacingOccurrences(of: "Dzień:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        continue
                    }

                    if !ths.isEmpty && texts.count >= 3 {
                        for (cIdx, rawH) in texts.enumerated() {
                            let h = ScheduleFilterMatcher.foldPolishDiacritics(rawH.lowercased())
                            if h.contains("lekc") || h.contains("godz") || h == "nr" { colPeriod = cIdx }
                            else if h.contains("nieobec") || h.contains("nauczyciel") || h.contains("wakat") { colAbsent = cIdx }
                            else if h.contains("oddz") || h.contains("klas") { colClass = cIdx }
                            else if h.contains("przedm") || h.contains("zajec") { colSubject = cIdx }
                            else if h.contains("sal") { colRoom = cIdx }
                            else if h.contains("zastepc") || h.contains("zastepuj") || h.contains("dyzuruj") { colSub = cIdx }
                            else if h.contains("uwag") || h.contains("opis") { colNote = cIdx }
                        }
                        startRow = idx + 1
                        break
                    }
                }

                for rIdx in startRow..<rows.count {
                    let row = rows[rIdx]
                    let ths = row.children().array().filter { $0.tagName().lowercased() == "th" }
                    if ths.count == 1,
                       let single = (try? ths[0].text().trimmingCharacters(in: .whitespacesAndNewlines)),
                       !single.isEmpty,
                       (single.localizedCaseInsensitiveContains("Dzień:") ||
                        single.range(of: "\\d{2}\\.\\d{2}\\.\\d{4}|\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil) {
                        currentDate = single.replacingOccurrences(of: "Dzień:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        continue
                    }
                    let tds = row.children().array().filter { $0.tagName().lowercased() == "td" }
                    if tds.isEmpty { continue }
                    let vals = tds.map { ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                    if vals.allSatisfy(\.isEmpty) { continue }

                    let periodRaw = (colPeriod >= 0 && colPeriod < vals.count) ? vals[colPeriod] : vals.first ?? ""
                    let absent = (colAbsent >= 0 && colAbsent < vals.count) ? vals[colAbsent] : ""
                    let className = (colClass >= 0 && colClass < vals.count) ? vals[colClass] : ""
                    let subject = (colSubject >= 0 && colSubject < vals.count) ? vals[colSubject] : ""
                    let room = (colRoom >= 0 && colRoom < vals.count) ? vals[colRoom] : ""
                    let sub = (colSub >= 0 && colSub < vals.count) ? vals[colSub] : ""
                    let note = (colNote >= 0 && colNote < vals.count) ? vals[colNote] : ""

                    var periodOnly = periodRaw
                    var timeRange = ""
                    if let commaIdx = periodRaw.firstIndex(of: ",") {
                        periodOnly = String(periodRaw[..<commaIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        timeRange = String(periodRaw[periodRaw.index(after: commaIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    let combined = "\(sub) \(note) \(subject)"
                    let groupTag = ScheduleFilterMatcher.detectGroupTag("\(className) \(subject) \(note)")
                    let isCancel = ScheduleFilterMatcher.isCancellationText(combined)

                    let itemId = "\(currentDate)_\(className)_\(periodOnly)_\(absent)_\(items.count)"
                    items.append(
                        SubstitutionItem(
                            id: itemId,
                            dateLabel: currentDate,
                            className: className,
                            period: periodOnly,
                            timeRange: timeRange,
                            absentTeacher: absent,
                            subject: subject,
                            substituteTeacher: sub,
                            room: room,
                            note: note,
                            groupTag: groupTag,
                            isCancellation: isCancel
                        )
                    )
                }
            }
        }

        let bodyText = (try? doc.body()?.text()) ?? ""
        let hasPasswordForm = ((try? doc.select("form input[type=password]").size()) ?? 0) > 0
        let authOk = !(hasPasswordForm && items.isEmpty && announcements.isEmpty && !bodyText.localizedCaseInsensitiveContains("zastępstw"))

        let hashInput = "\(dateHeading)|\(items.map { "\($0.dateLabel):\($0.className):\($0.period):\($0.subject):\($0.substituteTeacher):\($0.note)" }.joined(separator: ";"))|\(announcements.joined(separator: ";"))|\(notes.joined(separator: ";"))"

        return SubstitutionsSnapshot(
            dateHeading: dateHeading,
            items: items,
            announcements: Array(NSOrderedSet(array: announcements)) as? [String] ?? announcements,
            notes: Array(NSOrderedSet(array: notes)) as? [String] ?? notes,
            fetchedAtMillis: Int64(Date().timeIntervalSince1970 * 1000),
            rawHash: sha256(hashInput),
            authSucceeded: authOk,
            sourceUrl: sourceUrl
        )
    }

    static func aggregateTeacherScheduleFromTimetables(
        teacherAbbr: String,
        sourceTimetables: [ClassTimetable],
        sourceUrl: String
    ) -> ClassTimetable {
        let cleanAbbr = teacherAbbr.trimmingCharacters(in: .whitespacesAndNewlines)
        var lessonsByDay: [[String: LessonEntry]] = Array(repeating: [:], count: 5)

        for classPlan in sourceTimetables {
            let clsLabel = ScheduleFilterMatcher.extractPrimaryClassCode(classPlan.className)
            for day in classPlan.days where (0...4).contains(day.dayIndex) {
                for lesson in day.lessons {
                    let matches = ScheduleFilterMatcher.matchesTeacherToken(lesson.teacher, teacherAbbr: cleanAbbr) ||
                                  ScheduleFilterMatcher.matchesTeacherToken(lesson.rawText, teacherAbbr: cleanAbbr)
                    guard matches else { continue }
                    let slotKey = "\(lesson.period)|\(lesson.subject)|\(lesson.room)"
                    if var existing = lessonsByDay[day.dayIndex][slotKey] {
                        let existingParts = existing.classGroupLabel.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        if !existingParts.contains(clsLabel) && !clsLabel.isEmpty {
                            existing.classGroupLabel = (existingParts + [clsLabel]).joined(separator: ", ")
                            lessonsByDay[day.dayIndex][slotKey] = existing
                        }
                    } else {
                        var copy = lesson
                        copy.classGroupLabel = clsLabel
                        if copy.teacher.isEmpty { copy.teacher = cleanAbbr }
                        lessonsByDay[day.dayIndex][slotKey] = copy
                    }
                }
            }
        }

        let days = defaultDays.enumerated().map { idx, name in
            DaySchedule(
                dayIndex: idx,
                dayName: name,
                lessons: lessonsByDay[idx].values.sorted { $0.period < $1.period }
            )
        }
        return ClassTimetable(
            className: cleanAbbr,
            classUrl: sourceUrl,
            category: .teacher,
            generatedInfo: "Przeszukano plany: \(sourceTimetables.count)",
            days: days,
            fetchedAtMillis: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    static func extractTeacherTargets(from sourceTimetables: [ClassTimetable]) -> [TimetableTarget] {
        var found = Set<String>()
        for plan in sourceTimetables {
            for day in plan.days {
                for lesson in day.lessons {
                    let raw = lesson.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
                    if raw.isEmpty { continue }
                    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    for token in parts where !token.isEmpty && token != "-" && token != "—" {
                        found.insert(token)
                    }
                }
            }
        }
        return found.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { abbr in
            TimetableTarget(
                id: "teacher_\(abbr)",
                name: abbr,
                url: "teacher://\(abbr)",
                category: .teacher
            )
        }
    }

    static func resolveUrl(baseUrl: String, relative: String) -> String {
        let trimmedRel = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRel.isEmpty { return baseUrl }
        if let abs = URL(string: trimmedRel), abs.scheme != nil {
            return abs.absoluteString
        }
        if let base = URL(string: baseUrl), let resolved = URL(string: trimmedRel, relativeTo: base) {
            return resolved.absoluteURL.absoluteString
        }
        return trimmedRel
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
