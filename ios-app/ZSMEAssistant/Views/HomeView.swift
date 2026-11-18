import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: ZsmeViewModel
    let onOpenClassPicker: () -> Void
    let onOpenTimetable: () -> Void
    let onOpenSubstitutions: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if viewModel.preferences.userRole == .student && viewModel.preferences.selectedClassName.isEmpty {
                        onboardingCard
                    } else if viewModel.preferences.userRole == .teacher && viewModel.preferences.teacherAbbreviation.isEmpty {
                        teacherOnboardingCard
                    } else {
                        LiveStatusCardView(prepared: viewModel.preparedSchedule)
                        if let banner = viewModel.preparedSchedule.substitutionBanner {
                            substitutionBannerView(banner)
                        }
                        todayScheduleSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ZSME Assistant")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.refreshAll() }
                    } label: {
                        if viewModel.isRefreshingTimetable || viewModel.isRefreshingSubstitutions {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.refreshAll()
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(ZsmeTheme.cobalt.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: viewModel.preferences.userRole == .teacher ? "person.text.rectangle" : "graduationcap.fill")
                    .foregroundStyle(ZsmeTheme.cobalt)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.preferences.userRole == .teacher {
                    Text(viewModel.preferences.teacherAbbreviation.isEmpty ? "Tryb nauczyciela" : "Nauczyciel: \(viewModel.preferences.teacherAbbreviation)")
                        .font(.headline)
                    Text("plan.zsme.pl • sekretariat.zsme.pl")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let cls = viewModel.preferences.selectedClassName
                    Text(cls.isEmpty ? "Nie wybrano klasy" : ScheduleFilterMatcher.extractPrimaryClassCode(cls))
                        .font(.headline)
                    Text(cls.isEmpty ? "Wybierz klasę, aby śledzić plan" : "\(viewModel.preferences.selectedGroup.shortLabel) • ZSM-E")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(viewModel.preferences.userRole == .teacher ? "Konfiguruj" : "Zmień") {
                if viewModel.preferences.userRole == .teacher {
                    onOpenSettings()
                } else {
                    onOpenClassPicker()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("ZsmeBanner")
                .resizable()
                .scaledToFill()
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Witaj w ZSME Assistant na iOS")
                .font(.title3.bold())
            Text("Wybierz swoją klasę z planu plan.zsme.pl, aby na żywo śledzić pozostały czas lekcji, przerwy i zastępstwa z sekretariatu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onOpenClassPicker()
            } label: {
                Label("Wybierz swoją klasę", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ZsmeTheme.cobalt)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var teacherOnboardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skonfiguruj skrót nauczyciela")
                .font(.title3.bold())
            Text("Przejdź do Ustawień, wpisz swój dwuliterowy skrót z planu (np. JK) i zsynchronizuj swój plan oraz zastępstwa.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Otwórz Ustawienia", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .tint(ZsmeTheme.cobalt)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func substitutionBannerView(_ banner: String) -> some View {
        Button(action: onOpenSubstitutions) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(ZsmeTheme.amber)
                Text(banner)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(ZsmeTheme.amber.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var todayScheduleSection: some View {
        let prepared = viewModel.preparedSchedule
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(prepared.todayDayName.map { "Dzisiaj (\($0))" } ?? "Plan zajęć")
                    .font(.headline)
                Spacer()
                Button("Pełny tydzień", action: onOpenTimetable)
                    .font(.subheadline)
            }
            if prepared.todaySlots.isEmpty {
                Text("Brak zaplanowanych zajęć na dziś.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(prepared.todaySlots) { slot in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slot.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                VStack {
                                    Text("\(slot.period)")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(ZsmeTheme.cobalt)
                                    Text(slot.timeRangeLabel.split(separator: "-").first.map(String.init) ?? "")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 44)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.lesson.subject)
                                        .font(.subheadline.weight(.semibold))
                                    HStack(spacing: 6) {
                                        if !item.lesson.teacher.isEmpty {
                                            Text(item.lesson.teacher)
                                        }
                                        if !item.lesson.room.isEmpty {
                                            Text("• Sala \(item.lesson.room)")
                                        }
                                        if let g = item.lesson.groupTag {
                                            Text("• \(g)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    if let sub = item.substitution {
                                        Text("Zastępstwo: \(sub.substituteTeacher.isEmpty ? sub.note : sub.substituteTeacher)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(ZsmeTheme.amber)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

private struct LiveStatusCardView: View {
    let prepared: PreparedDaySchedule

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let eval = LiveScheduleTracker.evaluate(prepared: prepared, now: context.date)
            cardContent(eval: eval)
        }
    }

    @ViewBuilder
    private func cardContent(eval: LiveScheduleEvaluation) -> some View {
        switch eval.status {
        case .noTimetable:
            VStack(alignment: .leading, spacing: 8) {
                Text("Brak załadowanego planu")
                    .font(.headline)
                Text("Dotknij odświeżania lub wybierz klasę, aby pobrać plan lekcji.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

        case .duringLesson(let current, let remaining, let total, let next):
            let progress = max(0, min(1, Double(total - remaining) / Double(max(total, 1))))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Trwa lekcja \(current.period)", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ZsmeTheme.liveGreen)
                    Spacer()
                    Text(current.timeRangeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(LiveScheduleTracker.formatCountdown(remaining))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                ProgressView(value: progress)
                    .tint(ZsmeTheme.liveGreen)
                ForEach(current.items) { item in
                    HStack {
                        Text(item.substitution?.subject.isEmpty == false ? item.substitution!.subject : item.lesson.subject)
                            .font(.headline)
                        Spacer()
                        let room = item.substitution?.room.isEmpty == false ? item.substitution!.room : item.lesson.room
                        if !room.isEmpty {
                            Text("Sala \(room)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ZsmeTheme.cobalt)
                        }
                    }
                }
                if let next = next, let nextFirst = next.items.first {
                    Divider()
                    HStack {
                        Text("Następnie:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(nextFirst.lesson.subject) (\(next.timeRangeLabel))")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

        case .breakTime(_, let next, let remaining, let total):
            let progress = max(0, min(1, Double(total - remaining) / Double(max(total, 1))))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Przerwa międzylekcyjna", systemImage: "cup.and.saucer.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ZsmeTheme.amber)
                    Spacer()
                    Text("Do \(next.period) lekcji")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(LiveScheduleTracker.formatCountdown(remaining))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                ProgressView(value: progress)
                    .tint(ZsmeTheme.amber)
                if let nextFirst = next.items.first {
                    Text("Następna: \(nextFirst.lesson.subject) • Sala \(nextFirst.lesson.room.isEmpty ? "—" : nextFirst.lesson.room)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

        case .beforeLessons(let first, let remaining):
            VStack(alignment: .leading, spacing: 10) {
                Label("Przed lekcjami", systemImage: "sunrise.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ZsmeTheme.teal)
                Text("Start za \(LiveScheduleTracker.formatDurationWordsPl(remaining))")
                    .font(.title2.bold().monospacedDigit())
                if let firstItem = first.items.first {
                    Text("Pierwsza lekcja (\(first.timeRangeLabel)): \(firstItem.lesson.subject)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

        case .weekend(let nextLabel, let nextFirst), .afterLessons(let nextLabel, let nextFirst):
            VStack(alignment: .leading, spacing: 10) {
                Label(eval.todayDayIndex == nil ? "Weekend" : "Koniec zajęć na dziś", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ZsmeTheme.cobalt)
                if let nextLabel = nextLabel, let slot = nextFirst, let firstItem = slot.items.first {
                    Text("Najbliższe zajęcia: \(nextLabel)")
                        .font(.headline)
                    Text("\(slot.timeRangeLabel) • \(firstItem.lesson.subject)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Odpocznij i sprawdź jutrzejszy plan oraz zastępstwa.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}
