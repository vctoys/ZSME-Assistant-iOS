import Foundation
import Combine

enum SubstitutionsFilterTab: String, CaseIterable, Identifiable {
    case myGroup = "Moje / klasa"
    case all = "Wszystkie"
    var id: String { rawValue }
}

@MainActor
final class ZsmeViewModel: ObservableObject {
    @Published var preferences = UserPreferences()
    @Published var catalog = TimetableCatalog()
    @Published var timetable: ClassTimetable? { didSet { rebuildPreparedSchedule() } }
    @Published var inspectedTimetable: ClassTimetable?
    @Published var substitutions: SubstitutionsSnapshot? { didSet { rebuildPreparedSchedule() } }
    @Published private(set) var preparedSchedule = PreparedDaySchedule.empty

    @Published var selectedDayIndex: Int = 0
    @Published var selectedCategory: TimetableCategory = .schoolClass
    @Published var selectedSubTab: SubstitutionsFilterTab = .myGroup

    @Published var isRefreshingCatalog = false
    @Published var isRefreshingTimetable = false
    @Published var isRefreshingSubstitutions = false
    @Published var errorMessage: String?
    @Published var statusBanner: String?

    let portalClient = ZsmePortalClient()
    let calendarExporter = CalendarExporter()
    let meshManager = BleMeshManager()

    private let prefsKey = "zsme_user_preferences_v1"
    private var dayChangeObserver: AnyCancellable?

    init() {
        loadPreferences()
        loadCachedData()
        selectedDayIndex = ScheduleFilterMatcher.weekdayToZeroBasedIndex(Calendar.current.component(.weekday, from: Date())) ?? 0
        rebuildPreparedSchedule()
        dayChangeObserver = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildPreparedSchedule()
            }
        Task {
            await refreshAll(silent: true)
        }
    }

    func rebuildPreparedSchedule() {
        preparedSchedule = LiveScheduleTracker.prepareDaySchedule(
            timetable: timetable,
            substitutions: substitutions,
            userRole: preferences.userRole,
            selectedClassName: preferences.selectedClassName,
            selectedGroup: preferences.selectedGroup,
            customGroupFilter: preferences.customGroupFilter,
            teacherAbbr: preferences.teacherAbbreviation,
            teacherFullName: preferences.teacherFullName,
            now: Date()
        )
    }

    var activeDisplayedTimetable: ClassTimetable? {
        if preferences.userRole == .teacher {
            return timetable
        }
        if selectedCategory == .schoolClass {
            return timetable
        }
        return inspectedTimetable ?? timetable
    }

    var myGroupSubstitutions: [SubstitutionItem] {
        guard let items = substitutions?.items else { return [] }
        if preferences.userRole == .teacher {
            return items.filter {
                ScheduleFilterMatcher.matchesTeacherSubstitution(
                    item: $0,
                    teacherAbbr: preferences.teacherAbbreviation,
                    teacherFullName: preferences.teacherFullName
                ) != .none
            }
        }
        guard !preferences.selectedClassName.isEmpty else { return items }
        return items.filter {
            ScheduleFilterMatcher.matchesSubstitution(
                item: $0,
                selectedClassName: preferences.selectedClassName,
                selectedGroup: preferences.selectedGroup,
                customGroupFilter: preferences.customGroupFilter
            )
        }
    }

    func refreshAll(silent: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshCatalog(silent: silent) }
            group.addTask { await self.refreshSubstitutions(silent: silent) }
            group.addTask { await self.refreshPrimaryTimetable(silent: silent) }
        }
    }

    func refreshCatalog(silent: Bool = false) async {
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }
        do {
            let fetched = try await portalClient.fetchTimetableCatalog(baseUrl: preferences.planUrl)
            catalog = fetched
            saveCachedJSON(fetched, fileName: "catalog.json")
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func refreshPrimaryTimetable(silent: Bool = false) async {
        isRefreshingTimetable = true
        defer { isRefreshingTimetable = false }
        do {
            if preferences.userRole == .teacher {
                let schools = preferences.allTeacherSchools()
                guard let primary = schools.first else { return }
                let loaded = try await portalClient.fetchTeacherTimetable(school: primary, knownCatalog: catalog)
                timetable = loaded
                saveCachedJSON(loaded, fileName: "timetable.json")
            } else if !preferences.selectedClassUrl.isEmpty {
                let target = TimetableTarget(
                    id: preferences.selectedClassId,
                    name: preferences.selectedClassName,
                    url: preferences.selectedClassUrl,
                    category: .schoolClass
                )
                let loaded = try await portalClient.fetchTargetTimetable(target: target)
                timetable = loaded
                saveCachedJSON(loaded, fileName: "timetable.json")
            }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func inspectTarget(_ target: TimetableTarget) async {
        isRefreshingTimetable = true
        defer { isRefreshingTimetable = false }
        do {
            if target.category == .teacher && target.url.hasPrefix("teacher://") {
                let abbr = String(target.url.dropFirst("teacher://".count))
                let school = TeacherSchoolConfig(
                    id: "inspect_\(abbr)",
                    schoolName: UserPreferences.deriveSchoolLabel(url: preferences.planUrl, fallback: "ZSME"),
                    teacherAbbreviation: abbr,
                    planUrl: preferences.planUrl,
                    colorIndex: 0
                )
                let loaded = try await portalClient.fetchTeacherTimetable(school: school, knownCatalog: catalog)
                inspectedTimetable = loaded
            } else {
                let loaded = try await portalClient.fetchTargetTimetable(target: target)
                inspectedTimetable = loaded
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discoverTeachersIfNeeded() async {
        guard catalog.teachers.isEmpty, !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }
        if catalog.classes.isEmpty {
            await refreshCatalog(silent: true)
            return
        }
        let cleanBase = preferences.planUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = cleanBase.isEmpty ? UserPreferences.defaultPlanUrl : cleanBase
        let classPlans = await portalClient.fetchAllClassPlans(classes: catalog.classes, cacheKey: cacheKey, forceRefresh: false)
        let discovered = ZsmeHtmlParser.extractTeacherTargets(from: classPlans)
        if !discovered.isEmpty {
            catalog.teachers = discovered
            saveCachedJSON(catalog, fileName: "catalog.json")
        }
    }

    func refreshSubstitutions(silent: Bool = false) async {
        isRefreshingSubstitutions = true
        defer { isRefreshingSubstitutions = false }
        do {
            let snap = try await portalClient.fetchSubstitutions(
                accessKey: preferences.secretariatKey,
                baseUrl: preferences.substitutionsUrl
            )
            let previousHash = preferences.lastNotifiedSubstitutionsHash
            substitutions = snap
            saveCachedJSON(snap, fileName: "substitutions.json")

            if !snap.rawHash.isEmpty && snap.rawHash != previousHash {
                if !previousHash.isEmpty && preferences.notificationsEnabled {
                    let count = myGroupSubstitutions.count
                    let msg = count > 0
                        ? "Wykryto \(count) nowych zastępstw dla Twojej klasy/grupy."
                        : "Zaktualizowano tablicę zastępstw na sekretariat.zsme.pl."
                    NotificationManager.shared.sendLocalNotification(title: "Nowe zastępstwa ZSME", body: msg)
                    appendNotificationLog(title: "Nowe zastępstwa ZSME", message: msg, category: "SUBSTITUTION")
                }
                preferences.lastNotifiedSubstitutionsHash = snap.rawHash
                savePreferences()
            }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    func selectClass(_ schoolClass: SchoolClass) {
        preferences.userRole = .student
        preferences.selectedClassId = schoolClass.id
        preferences.selectedClassName = schoolClass.name
        preferences.selectedClassUrl = schoolClass.url
        selectedCategory = .schoolClass
        savePreferences()
        rebuildPreparedSchedule()
        Task {
            await refreshPrimaryTimetable(silent: false)
        }
    }

    func updateGroup(_ group: StudentGroup) {
        preferences.selectedGroup = group
        savePreferences()
        rebuildPreparedSchedule()
    }

    func updatePreferences(_ mutate: (inout UserPreferences) -> Void) {
        mutate(&preferences)
        savePreferences()
        rebuildPreparedSchedule()
    }

    func appendNotificationLog(title: String, message: String, category: String) {
        let entry = NotificationLogEntry(
            id: UUID().uuidString,
            title: title,
            message: message,
            timestampMillis: Int64(Date().timeIntervalSince1970 * 1000),
            category: category
        )
        preferences.recentNotifications = ([entry] + preferences.recentNotifications).prefix(30).map { $0 }
        savePreferences()
    }

    func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }

    private func loadPreferences() {
        if let data = UserDefaults.standard.data(forKey: prefsKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            preferences = decoded
        }
    }

    private func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ZSMECache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveCachedJSON<T: Encodable>(_ value: T, fileName: String) {
        let url = cacheDirectory().appendingPathComponent(fileName)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url)
        }
    }

    private func loadCachedData() {
        if let data = try? Data(contentsOf: cacheDirectory().appendingPathComponent("catalog.json")),
           let decoded = try? JSONDecoder().decode(TimetableCatalog.self, from: data) {
            catalog = decoded
        }
        if let data = try? Data(contentsOf: cacheDirectory().appendingPathComponent("timetable.json")),
           let decoded = try? JSONDecoder().decode(ClassTimetable.self, from: data) {
            timetable = decoded
        }
        if let data = try? Data(contentsOf: cacheDirectory().appendingPathComponent("substitutions.json")),
           let decoded = try? JSONDecoder().decode(SubstitutionsSnapshot.self, from: data) {
            substitutions = decoded
        }
    }
}
