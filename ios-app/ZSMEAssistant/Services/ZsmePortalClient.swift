import Foundation

enum ZsmePortalError: LocalizedError {
    case invalidUrl(String)
    case httpError(Int)
    case decodingError
    case networkError(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidUrl(let u): return "Nieprawidłowy adres URL: \(u)"
        case .httpError(let code): return "Serwer szkoły zwrócił błąd HTTP \(code)."
        case .decodingError: return "Nie udało się odczytać odpowiedzi serwera."
        case .networkError(let msg): return msg
        case .message(let msg): return msg
        }
    }

    static func describe(_ error: Error) -> String {
        if let portalErr = error as? ZsmePortalError {
            return portalErr.errorDescription ?? "Wystąpił błąd połączenia z portalem."
        }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Brak połączenia z internetem. Wyświetlam zapisane dane z pamięci."
            case .timedOut:
                return "Przekroczono czas oczekiwania na odpowiedź serwera szkoły."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Nie można połączyć się z serwerem plan.zsme.pl / sekretariat.zsme.pl."
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "Błąd certyfikatu HTTPS podczas łączenia z portalem."
            case .cancelled:
                return "Żądanie zostało anulowane."
            default:
                return "Błąd sieci (\(urlErr.errorCode)): \(urlErr.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}

private actor ClassPlanMemoryCache {
    private var cache: [String: [ClassTimetable]] = [:]

    func get(_ baseUrl: String) -> [ClassTimetable]? {
        cache[baseUrl]
    }

    func set(_ plans: [ClassTimetable], for baseUrl: String) {
        cache[baseUrl] = plans
    }
}

final class ZsmePortalClient {
    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    private let classPlanCache = ClassPlanMemoryCache()

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        self.session = URLSession(configuration: config)
    }

    func fetchTimetableCatalog(baseUrl: String = UserPreferences.defaultPlanUrl) async throws -> TimetableCatalog {
        let cleanBase = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBase = cleanBase.isEmpty ? UserPreferences.defaultPlanUrl : cleanBase

        let root = try await fetchHtml(url: effectiveBase)
        var classes: [String: SchoolClass] = [:]
        var teachers: [String: TimetableTarget] = [:]
        var rooms: [String: TimetableTarget] = [:]

        func merge(_ part: TimetableCatalog) {
            for c in part.classes { classes[c.url] = classes[c.url] ?? c }
            for t in part.teachers { teachers[t.url] = teachers[t.url] ?? t }
            for r in part.rooms { rooms[r.url] = rooms[r.url] ?? r }
        }

        merge(ZsmeHtmlParser.parseTimetableCatalog(html: root.html, baseUrl: root.finalUrl))

        var candidateUrls = ZsmeHtmlParser.extractFrameUrls(html: root.html, baseUrl: root.finalUrl) +
                            ZsmeHtmlParser.extractCatalogSubpageUrls(html: root.html, baseUrl: root.finalUrl) +
                            [
                                ZsmeHtmlParser.resolveUrl(baseUrl: root.finalUrl, relative: "lista.html"),
                                ZsmeHtmlParser.resolveUrl(baseUrl: root.finalUrl, relative: "plany/lista.html")
                            ]
        candidateUrls = Array(NSOrderedSet(array: candidateUrls)) as? [String] ?? candidateUrls

        var visited = Set([root.finalUrl])
        for url in candidateUrls where !visited.contains(url) {
            visited.insert(url)
            if let page = try? await fetchHtml(url: url) {
                visited.insert(page.finalUrl)
                merge(ZsmeHtmlParser.parseTimetableCatalog(html: page.html, baseUrl: page.finalUrl))
            }
        }

        let sortedClasses = classes.values.sorted { a, b in
            let na = Int(a.name.prefix(while: \.isNumber)) ?? 99
            let nb = Int(b.name.prefix(while: \.isNumber)) ?? 99
            return na != nb ? na < nb : a.name < b.name
        }
        var sortedTeachers = teachers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let sortedRooms = rooms.values.sorted { a, b in
            let na = Int(a.name.prefix(while: \.isNumber)) ?? Int.max
            let nb = Int(b.name.prefix(while: \.isNumber)) ?? Int.max
            return na != nb ? na < nb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        if sortedTeachers.isEmpty && !sortedClasses.isEmpty {
            let classPlans = await fetchAllClassPlans(classes: sortedClasses, cacheKey: effectiveBase, forceRefresh: true)
            sortedTeachers = ZsmeHtmlParser.extractTeacherTargets(from: classPlans)
        }

        let catalog = TimetableCatalog(
            classes: sortedClasses,
            teachers: sortedTeachers,
            rooms: sortedRooms
        )

        if catalog.classes.isEmpty && catalog.teachers.isEmpty && catalog.rooms.isEmpty {
            throw ZsmePortalError.message("Nie znaleziono listy planów pod adresem \(effectiveBase)")
        }
        return catalog
    }

    func fetchAllClassPlans(
        classes: [SchoolClass],
        cacheKey: String,
        forceRefresh: Bool = false
    ) async -> [ClassTimetable] {
        if !forceRefresh, let cached = await classPlanCache.get(cacheKey), !cached.isEmpty {
            return cached
        }
        var classPlans: [ClassTimetable] = []
        await withTaskGroup(of: ClassTimetable?.self) { group in
            for cls in classes {
                group.addTask {
                    let target = TimetableTarget(id: cls.id, name: cls.name, url: cls.url, category: .schoolClass)
                    return try? await self.fetchTargetTimetable(target: target)
                }
            }
            for await plan in group {
                if let p = plan { classPlans.append(p) }
            }
        }
        if !classPlans.isEmpty {
            await classPlanCache.set(classPlans, for: cacheKey)
        }
        return classPlans
    }

    func fetchTargetTimetable(target: TimetableTarget) async throws -> ClassTimetable {
        let page = try await fetchHtml(url: target.url)
        let parsed = ZsmeHtmlParser.parseTimetable(
            html: page.html,
            className: target.name,
            classUrl: page.finalUrl,
            category: target.category
        )
        if parsed.days.allSatisfy({ $0.lessons.isEmpty }) && !ZsmeHtmlParser.hasTimetableStructure(html: page.html) {
            throw ZsmePortalError.message("Plan dla „\(target.name)” ma nierozpoznany format.")
        }
        return parsed
    }

    func fetchTeacherTimetable(
        school: TeacherSchoolConfig,
        knownCatalog: TimetableCatalog
    ) async throws -> ClassTimetable {
        let catalog: TimetableCatalog
        if knownCatalog.classes.isEmpty && knownCatalog.teachers.isEmpty {
            catalog = try await fetchTimetableCatalog(baseUrl: school.planUrl)
        } else {
            catalog = knownCatalog
        }

        if let direct = catalog.teachers.first(where: {
            !$0.url.hasPrefix("teacher://") &&
            ($0.name.caseInsensitiveCompare(school.teacherAbbreviation) == .orderedSame ||
             ScheduleFilterMatcher.matchesTeacherToken($0.name, teacherAbbr: school.teacherAbbreviation))
        }) {
            if var parsed = try? await fetchTargetTimetable(target: direct),
               parsed.days.contains(where: { !$0.lessons.isEmpty }) {
                parsed.days = parsed.days.map { day in
                    DaySchedule(
                        dayIndex: day.dayIndex,
                        dayName: day.dayName,
                        lessons: day.lessons.map { l in
                            var copy = l
                            copy.schoolId = school.id
                            copy.schoolName = school.schoolName
                            copy.schoolColorIndex = school.colorIndex
                            return copy
                        }
                    )
                }
                return parsed
            }
        }

        let cleanBase = school.planUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = cleanBase.isEmpty ? UserPreferences.defaultPlanUrl : cleanBase
        let classPlans = await fetchAllClassPlans(classes: catalog.classes, cacheKey: cacheKey, forceRefresh: false)

        var aggregated = ZsmeHtmlParser.aggregateTeacherScheduleFromTimetables(
            teacherAbbr: school.teacherAbbreviation,
            sourceTimetables: classPlans,
            sourceUrl: school.planUrl
        )
        aggregated.days = aggregated.days.map { day in
            DaySchedule(
                dayIndex: day.dayIndex,
                dayName: day.dayName,
                lessons: day.lessons.map { l in
                    var copy = l
                    copy.schoolId = school.id
                    copy.schoolName = school.schoolName
                    copy.schoolColorIndex = school.colorIndex
                    return copy
                }
            )
        }
        return aggregated
    }

    func fetchSubstitutions(
        accessKey: String = UserPreferences.defaultSecretariatKey,
        baseUrl: String = UserPreferences.defaultSubstitutionsUrl
    ) async throws -> SubstitutionsSnapshot {
        let cleanUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetUrl = cleanUrl.isEmpty ? UserPreferences.defaultSubstitutionsUrl : cleanUrl

        var page = try await fetchHtmlWithOptionalBasicAuth(url: targetUrl, accessKey: accessKey)
        if let authForm = ZsmeHtmlParser.detectAuthForm(html: page.html, currentUrl: page.finalUrl, accessKey: accessKey) {
            page = try await submitForm(authForm)
        }

        var snapshot = ZsmeHtmlParser.parseSubstitutions(html: page.html, sourceUrl: page.finalUrl)

        if snapshot.items.isEmpty {
            for frameUrl in ZsmeHtmlParser.extractFrameUrls(html: page.html, baseUrl: page.finalUrl) {
                if let subPage = try? await fetchHtmlWithOptionalBasicAuth(url: frameUrl, accessKey: accessKey) {
                    let parsed = ZsmeHtmlParser.parseSubstitutions(html: subPage.html, sourceUrl: subPage.finalUrl)
                    if !parsed.items.isEmpty || !parsed.announcements.isEmpty {
                        snapshot = parsed
                        break
                    }
                }
            }
        }

        if snapshot.items.isEmpty && !targetUrl.localizedCaseInsensitiveContains("tv.php"),
           let subpage = ZsmeHtmlParser.findSubstitutionSubpageUrl(html: page.html, currentUrl: page.finalUrl),
           let subPage = try? await fetchHtmlWithOptionalBasicAuth(url: subpage, accessKey: accessKey) {
            var resolved = subPage
            if let form = ZsmeHtmlParser.detectAuthForm(html: subPage.html, currentUrl: subPage.finalUrl, accessKey: accessKey) {
                resolved = (try? await submitForm(form)) ?? subPage
            }
            let parsed = ZsmeHtmlParser.parseSubstitutions(html: resolved.html, sourceUrl: resolved.finalUrl)
            if !parsed.items.isEmpty || !parsed.announcements.isEmpty {
                snapshot = parsed
            }
        }

        return snapshot
    }

    private func fetchHtmlWithOptionalBasicAuth(url: String, accessKey: String) async throws -> (finalUrl: String, html: String) {
        guard let parsedUrl = URL(string: url) else { throw ZsmePortalError.invalidUrl(url) }
        var req = URLRequest(url: parsedUrl)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("pl-PL,pl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ZsmePortalError.decodingError }

        if http.statusCode == 401 && !accessKey.isEmpty {
            for user in ["uczen", "zsme", ""] {
                let cred = Data("\(user):\(accessKey)".utf8).base64EncodedString()
                var authReq = req
                authReq.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
                if let (aData, aResp) = try? await session.data(for: authReq),
                   let aHttp = aResp as? HTTPURLResponse,
                   (200..<300).contains(aHttp.statusCode) {
                    return (aResp.url?.absoluteString ?? url, decodeHtml(aData, response: aHttp))
                }
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ZsmePortalError.httpError(http.statusCode)
        }
        return (response.url?.absoluteString ?? url, decodeHtml(data, response: http))
    }

    private func fetchHtml(url: String) async throws -> (finalUrl: String, html: String) {
        do {
            return try await executeGet(url: url)
        } catch {
            if url.lowercased().hasPrefix("https://") {
                let httpFallback = "http://" + url.dropFirst(8)
                if let res = try? await executeGet(url: httpFallback) {
                    return res
                }
            }
            throw error
        }
    }

    private func executeGet(url: String) async throws -> (finalUrl: String, html: String) {
        guard let parsedUrl = URL(string: url) else { throw ZsmePortalError.invalidUrl(url) }
        var req = URLRequest(url: parsedUrl)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("pl-PL,pl;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ZsmePortalError.decodingError }
        guard (200..<300).contains(http.statusCode) else { throw ZsmePortalError.httpError(http.statusCode) }
        return (response.url?.absoluteString ?? url, decodeHtml(data, response: http))
    }

    private func submitForm(_ payload: AuthFormPayload) async throws -> (finalUrl: String, html: String) {
        guard let baseUrl = URL(string: payload.actionUrl) else { throw ZsmePortalError.invalidUrl(payload.actionUrl) }
        var req: URLRequest
        if payload.method == "GET" {
            var comps = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false)
            comps?.queryItems = payload.fields.map { URLQueryItem(name: $0.key, value: $0.value) }
            req = URLRequest(url: comps?.url ?? baseUrl)
            req.httpMethod = "GET"
        } else {
            req = URLRequest(url: baseUrl)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.setValue(payload.actionUrl, forHTTPHeaderField: "Referer")
            let bodyStr = payload.fields.map { k, v in
                let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
                let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                return "\(ek)=\(ev)"
            }.joined(separator: "&")
            req.httpBody = bodyStr.data(using: .utf8)
        }
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ZsmePortalError.message("Błąd logowania do sekretariatu")
        }
        return (response.url?.absoluteString ?? payload.actionUrl, decodeHtml(data, response: http))
    }

    private func decodeHtml(_ data: Data, response: HTTPURLResponse) -> String {
        if let textEncodingName = response.textEncodingName {
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
            if cfEnc != kCFStringEncodingInvalidId {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
                if let str = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
                    return str
                }
            }
        }
        let peek = String(data: data.prefix(4096), encoding: .isoLatin1)?.lowercased() ?? ""
        if peek.contains("iso-8859-2"), let str = String(data: data, encoding: .isoLatin2) {
            return str
        }
        if peek.contains("windows-1250") {
            let win1250 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue))
            if let str = String(data: data, encoding: String.Encoding(rawValue: win1250)) {
                return str
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin2) ?? String(decoding: data, as: UTF8.self)
    }
}
