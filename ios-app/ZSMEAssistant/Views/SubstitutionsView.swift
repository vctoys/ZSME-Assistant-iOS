import SwiftUI

struct SubstitutionsView: View {
    @ObservedObject var viewModel: ZsmeViewModel
    let onOpenClassPicker: () -> Void
    @State private var showPortalSheet = false
    @State private var showHistory = false

    private var displayedItems: [SubstitutionItem] {
        let all = viewModel.substitutions?.items ?? []
        return viewModel.selectedSubTab == .myGroup ? viewModel.myGroupSubstitutions : all
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Zakres", selection: $viewModel.selectedSubTab) {
                        ForEach(SubstitutionsFilterTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                if let subErr = viewModel.substitutionsError {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(subErr, systemImage: "wifi.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(ZsmeTheme.crimson)
                            Button("Spróbuj ponownie") {
                                Task { await viewModel.refreshSubstitutions(silent: false) }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                } else if viewModel.substitutions?.authSucceeded == false {
                    Section {
                        Label("Nie udało się odczytać zastępstw — sprawdź klucz sekretariatu w Ustawieniach.", systemImage: "key.slash")
                            .font(.caption)
                            .foregroundStyle(ZsmeTheme.amber)
                    }
                }

                if let heading = viewModel.substitutions?.dateHeading, !heading.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(ZsmeTheme.cobalt)
                            Text(heading)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Źródło WWW") { showPortalSheet = true }
                                .font(.caption)
                        }
                    }
                }

                if let announcements = viewModel.substitutions?.announcements, !announcements.isEmpty {
                    Section("Informacje") {
                        ForEach(announcements, id: \.self) { info in
                            Label(info, systemImage: "info.circle")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Zastępstwa (\(displayedItems.count))") {
                    if viewModel.isRefreshingSubstitutions && displayedItems.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Pobieranie z sekretariat.zsme.pl...")
                                .foregroundStyle(.secondary)
                        }
                    } else if displayedItems.isEmpty {
                        VStack(spacing: 12) {
                            Image("NoSubstitutions")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(viewModel.selectedSubTab == .myGroup
                                 ? "Brak zastępstw dla Twojej klasy i grupy."
                                 : "Brak opublikowanych zastępstw na stronie.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            if viewModel.preferences.selectedClassName.isEmpty && viewModel.preferences.userRole == .student {
                                Button("Wybierz klasę", action: onOpenClassPicker)
                                    .buttonStyle(.borderedProminent)
                                    .tint(ZsmeTheme.cobalt)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(displayedItems) { item in
                            SubstitutionRowView(item: item)
                        }
                    }
                }

                if let notes = viewModel.substitutions?.notes, !notes.isEmpty {
                    Section("Uwagi") {
                        ForEach(notes, id: \.self) { note in
                            Text(note)
                                .font(.subheadline)
                        }
                    }
                }

                if !viewModel.preferences.recentNotifications.isEmpty {
                    Section {
                        DisclosureGroup("Historia powiadomień (\(viewModel.preferences.recentNotifications.count))", isExpanded: $showHistory) {
                            ForEach(viewModel.preferences.recentNotifications) { log in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.title).font(.caption.weight(.semibold))
                                    Text(log.message).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Zastępstwa")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.refreshSubstitutions() }
                    } label: {
                        if viewModel.isRefreshingSubstitutions {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.refreshSubstitutions()
            }
            .sheet(isPresented: $showPortalSheet) {
                PortalWebViewSheet(
                    urlString: viewModel.preferences.substitutionsUrl,
                    title: "sekretariat.zsme.pl"
                )
            }
        }
    }
}

private struct SubstitutionRowView: View {
    let item: SubstitutionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.className.isEmpty ? "Ogólne" : item.className)
                    .font(.headline)
                    .foregroundStyle(item.isCancellation ? ZsmeTheme.crimson : ZsmeTheme.cobalt)
                if !item.period.isEmpty {
                    Text("• Lekcja \(item.period)")
                        .font(.subheadline.weight(.medium))
                }
                if !item.timeRange.isEmpty {
                    Text("(\(item.timeRange))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !item.room.isEmpty {
                    Text("Sala \(item.room)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !item.subject.isEmpty {
                Text(item.subject)
                    .font(.subheadline.weight(.medium))
            }

            HStack(spacing: 6) {
                if !item.absentTeacher.isEmpty {
                    Text("Nieobecny: \(item.absentTeacher)")
                        .foregroundStyle(.secondary)
                }
                if !item.substituteTeacher.isEmpty {
                    Text("→ \(item.substituteTeacher)")
                        .fontWeight(.semibold)
                        .foregroundStyle(item.isCancellation ? ZsmeTheme.crimson : ZsmeTheme.liveGreen)
                }
            }
            .font(.caption)

            if !item.note.isEmpty {
                Text(item.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
