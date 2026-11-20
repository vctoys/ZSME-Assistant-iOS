import SwiftUI

struct TimetableView: View {
    @ObservedObject var viewModel: ZsmeViewModel
    let onOpenClassPicker: () -> Void

    @State private var showTargetPicker = false
    @State private var showCalendarExport = false
    @State private var showPortalSheet = false
    @State private var targetSearchQuery = ""

    private let dayLabels = ["Pn", "Wt", "Śr", "Cz", "Pt"]
    private let fullDayLabels = ["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek"]

    private var displayedTimetable: ClassTimetable? {
        viewModel.activeDisplayedTimetable
    }

    private var dayLessons: [LessonEntry] {
        guard let tt = displayedTimetable,
              let day = tt.days.first(where: { $0.dayIndex == viewModel.selectedDayIndex }) else {
            return []
        }
        if viewModel.preferences.userRole == .teacher || viewModel.selectedCategory != .schoolClass {
            return day.lessons
        }
        return day.lessons.filter { lesson in
            ScheduleFilterMatcher.matchesGroup(
                groupTag: lesson.groupTag,
                combinedText: "\(lesson.subject) \(lesson.rawText)",
                selectedGroup: viewModel.preferences.selectedGroup,
                customGroupFilter: viewModel.preferences.customGroupFilter
            )
        }
    }

    private var daySubResolution: ClassDaySubstitutionResolution {
        guard viewModel.preferences.userRole == .student,
              viewModel.selectedCategory == .schoolClass,
              let tt = displayedTimetable else {
            return ClassDaySubstitutionResolution()
        }
        return ScheduleFilterMatcher.resolveClassDaySubstitutions(
            dayLessons: dayLessons,
            dayIndex: viewModel.selectedDayIndex,
            todayWeekdayIndex: ScheduleFilterMatcher.weekdayToZeroBasedIndex(Calendar.current.component(.weekday, from: Date())),
            snapshot: viewModel.substitutions,
            className: tt.className,
            selectedGroup: viewModel.preferences.selectedGroup,
            customGroupFilter: viewModel.preferences.customGroupFilter
        )
    }

    private var navigationTitleText: String {
        if let name = displayedTimetable?.className, !name.isEmpty {
            return ScheduleFilterMatcher.extractPrimaryClassCode(name)
        }
        return "Plan lekcji"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlsBar
                daySelectorBar
                Divider()

                List {
                    if let banner = daySubResolution.summaryBanner {
                        Section {
                            Label(banner, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(ZsmeTheme.amber)
                        }
                    }

                    if let err = viewModel.timetableError {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(err, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(ZsmeTheme.crimson)
                                Button("Odśwież plan") {
                                    Task { await viewModel.refreshPrimaryTimetable(silent: false) }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }

                    if viewModel.isRefreshingTimetable && dayLessons.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Wczytywanie planu lekcji...")
                                .foregroundStyle(.secondary)
                        }
                    } else if dayLessons.isEmpty {
                        let safeDayName = fullDayLabels.indices.contains(viewModel.selectedDayIndex)
                            ? fullDayLabels[viewModel.selectedDayIndex]
                            : "wybranym dniu"
                        VStack(spacing: 10) {
                            Text(displayedTimetable == nil
                                 ? "Wybierz klasę, nauczyciela lub salę, aby wyświetlić plan."
                                 : "Brak lekcji w dniu \(safeDayName).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            if displayedTimetable == nil {
                                Button("Wybierz klasę", action: onOpenClassPicker)
                                    .buttonStyle(.borderedProminent)
                                    .tint(ZsmeTheme.cobalt)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(Array(dayLessons.enumerated()), id: \.offset) { idx, lesson in
                            let sub = daySubResolution.byLessonIndex[idx]
                            LessonRowCard(lesson: lesson, substitution: sub)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showCalendarExport = true
                        } label: {
                            Label("Eksportuj do Kalendarza Apple", systemImage: "calendar.badge.plus")
                        }
                        Button {
                            showPortalSheet = true
                        } label: {
                            Label("Otwórz plan.zsme.pl", systemImage: "safari")
                        }
                        Button {
                            Task { await viewModel.refreshPrimaryTimetable() }
                        } label: {
                            Label("Odśwież plan", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showTargetPicker) {
                targetPickerSheet
            }
            .sheet(isPresented: $showCalendarExport) {
                CalendarExportSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showPortalSheet) {
                PortalWebViewSheet(
                    urlString: displayedTimetable?.classUrl ?? viewModel.preferences.planUrl,
                    title: "plan.zsme.pl"
                )
            }
        }
    }

    private var controlsBar: some View {
        VStack(spacing: 8) {
            if viewModel.preferences.userRole == .student {
                Picker("Kategoria", selection: $viewModel.selectedCategory) {
                    ForEach(TimetableCategory.allCases) { cat in
                        Text(cat.label).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedCategory) { newCat in
                    if newCat != .schoolClass {
                        showTargetPicker = true
                    }
                }
            }

            HStack(spacing: 8) {
                if viewModel.selectedCategory == .schoolClass && viewModel.preferences.userRole == .student {
                    Menu {
                        ForEach(StudentGroup.allCases) { grp in
                            Button {
                                viewModel.updateGroup(grp)
                            } label: {
                                if grp == viewModel.preferences.selectedGroup {
                                    Label(grp.displayName, systemImage: "checkmark")
                                } else {
                                    Text(grp.displayName)
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.preferences.selectedGroup.shortLabel, systemImage: "person.2")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                    Button("Zmień klasę", action: onOpenClassPicker)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button {
                        showTargetPicker = true
                    } label: {
                        Label("Wybierz z katalogu (\(viewModel.selectedCategory.label))", systemImage: "magnifyingglass")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var daySelectorBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { idx in
                Button {
                    viewModel.selectedDayIndex = idx
                } label: {
                    Text(dayLabels[idx])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewModel.selectedDayIndex == idx ? ZsmeTheme.cobalt : Color(.secondarySystemBackground))
                        .foregroundStyle(viewModel.selectedDayIndex == idx ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private var targetPickerSheet: some View {
        let targets: [TimetableTarget]
        switch viewModel.selectedCategory {
        case .schoolClass:
            targets = viewModel.catalog.classes.map {
                TimetableTarget(id: $0.id, name: $0.name, url: $0.url, category: .schoolClass)
            }
        case .teacher:
            targets = viewModel.catalog.teachers
        case .room:
            targets = viewModel.catalog.rooms
        }
        let trimmedQuery = targetSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedQuery.isEmpty
            ? targets
            : targets.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }

        return NavigationStack {
            List {
                if viewModel.selectedCategory == .teacher && !trimmedQuery.isEmpty && !filtered.contains(where: { $0.name.caseInsensitiveCompare(trimmedQuery) == .orderedSame }) {
                    Button {
                        let abbr = trimmedQuery.uppercased()
                        let custom = TimetableTarget(
                            id: "teacher_\(abbr)",
                            name: abbr,
                            url: "teacher://\(abbr)",
                            category: .teacher
                        )
                        showTargetPicker = false
                        Task { await viewModel.inspectTarget(custom) }
                    } label: {
                        Label("Wyszukaj plan nauczyciela „\(trimmedQuery.uppercased())”", systemImage: "magnifyingglass")
                            .foregroundStyle(ZsmeTheme.cobalt)
                    }
                }

                if viewModel.isRefreshingCatalog && targets.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(viewModel.selectedCategory == .teacher
                             ? "Skanowanie skrótów nauczycieli z planów klas..."
                             : "Pobieranie katalogu...")
                            .foregroundStyle(.secondary)
                    }
                } else if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.selectedCategory == .teacher
                             ? "Wpisz wyżej 2–3 literowy skrót nauczyciela (np. KS, MO) albo odśwież listę."
                             : "Brak pozycji do wyświetlenia.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Odśwież katalog") {
                            Task {
                                if viewModel.selectedCategory == .teacher {
                                    await viewModel.discoverTeachersIfNeeded()
                                } else {
                                    await viewModel.refreshCatalog()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(filtered) { target in
                        Button {
                            showTargetPicker = false
                            Task { await viewModel.inspectTarget(target) }
                        } label: {
                            HStack {
                                Text(target.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if target.category == .teacher && target.url.hasPrefix("teacher://") {
                                    Text("Skrót z planu")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $targetSearchQuery, prompt: viewModel.selectedCategory == .teacher ? "Wpisz skrót nauczyciela (np. KS)..." : "Szukaj...")
            .navigationTitle(viewModel.selectedCategory.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { showTargetPicker = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.refreshCatalog()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if viewModel.selectedCategory == .teacher && viewModel.catalog.teachers.isEmpty {
                    await viewModel.discoverTeachersIfNeeded()
                }
            }
        }
    }
}

private struct LessonRowCard: View {
    let lesson: LessonEntry
    let substitution: SubstitutionItem?

    var body: some View {
        let isCancelled = substitution?.isCancellation == true
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text("\(lesson.period)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isCancelled ? ZsmeTheme.crimson : ZsmeTheme.cobalt)
                if !lesson.timeRange.isEmpty {
                    Text(lesson.timeRange)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(isCancelled, color: ZsmeTheme.crimson)
                    .foregroundStyle(isCancelled ? .secondary : .primary)

                HStack(spacing: 6) {
                    if !lesson.teacher.isEmpty {
                        Text(lesson.teacher)
                    }
                    if !lesson.room.isEmpty {
                        Text("• Sala \(lesson.room)")
                    }
                    if !lesson.classGroupLabel.isEmpty {
                        Text("• \(lesson.classGroupLabel)")
                    }
                    if let g = lesson.groupTag {
                        Text("• \(g)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let sub = substitution {
                    Text(isCancelled
                         ? "Odwołane: \(sub.substituteTeacher.isEmpty ? sub.note : sub.substituteTeacher)"
                         : "Zastępstwo: \(sub.substituteTeacher) \(sub.room.isEmpty ? "" : "• Sala \(sub.room)")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCancelled ? ZsmeTheme.crimson : ZsmeTheme.amber)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CalendarExportSheet: View {
    @ObservedObject var viewModel: ZsmeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var startWeek: CalendarStartWeekMode = .currentWeek
    @State private var recurrence: CalendarRecurrenceMode = .untilEndOfSchoolYear
    @State private var calendarTitle = ""
    @State private var isExporting = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Konfiguracja eksportu do Kalendarza Apple") {
                    TextField("Nazwa kalendarza", text: $calendarTitle)
                    Picker("Początek", selection: $startWeek) {
                        ForEach(CalendarStartWeekMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Picker("Powtarzanie", selection: $recurrence) {
                        ForEach(CalendarRecurrenceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                if let resultMessage = resultMessage {
                    Section("Wynik") {
                        Text(resultMessage)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        Task { await runExport() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Label("Zapisz w Kalendarzu Apple (EventKit)", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(isExporting || viewModel.activeDisplayedTimetable == nil)
                }
            }
            .navigationTitle("Eksport do kalendarza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
            .onAppear {
                if calendarTitle.isEmpty {
                    let cls = viewModel.activeDisplayedTimetable?.className ?? "ZSME"
                    calendarTitle = "Plan lekcji — \(ScheduleFilterMatcher.extractPrimaryClassCode(cls))"
                }
            }
        }
    }

    private func runExport() async {
        guard let tt = viewModel.activeDisplayedTimetable else { return }
        isExporting = true
        defer { isExporting = false }

        var byDay: [Int: [LessonEntry]] = [:]
        for day in tt.days {
            if viewModel.preferences.userRole == .teacher {
                byDay[day.dayIndex] = day.lessons
            } else {
                byDay[day.dayIndex] = day.lessons.filter {
                    ScheduleFilterMatcher.matchesGroup(
                        groupTag: $0.groupTag,
                        combinedText: "\($0.subject) \($0.rawText)",
                        selectedGroup: viewModel.preferences.selectedGroup,
                        customGroupFilter: viewModel.preferences.customGroupFilter
                    )
                }
            }
        }

        do {
            let count = try await viewModel.calendarExporter.exportToAppleCalendar(
                timetable: tt,
                filteredLessonsByDay: byDay,
                calendarTitle: calendarTitle.isEmpty ? "Plan lekcji ZSME" : calendarTitle,
                startWeekMode: startWeek,
                recurrenceMode: recurrence
            )
            resultMessage = "Dodano \(count) wydarzeń do kalendarza „\(calendarTitle)”."
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}
