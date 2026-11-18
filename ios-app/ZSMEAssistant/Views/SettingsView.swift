import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ZsmeViewModel
    let onOpenClassPicker: () -> Void

    @State private var showTeacherPasswordAlert = false
    @State private var teacherPasswordInput = ""
    @State private var teacherPasswordError = false

    @State private var teacherAbbrDraft = ""
    @State private var planUrlDraft = ""
    @State private var subsUrlDraft = ""
    @State private var secKeyDraft = ""
    @State private var meshNickDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Tryb aplikacji") {
                    Picker("Rola", selection: Binding(
                        get: { viewModel.preferences.userRole },
                        set: { newRole in
                            if newRole == .teacher && viewModel.preferences.userRole != .teacher {
                                teacherPasswordInput = ""
                                teacherPasswordError = false
                                showTeacherPasswordAlert = true
                            } else {
                                viewModel.updatePreferences { $0.userRole = newRole }
                                Task { await viewModel.refreshPrimaryTimetable(silent: true) }
                            }
                        }
                    )) {
                        ForEach(UserRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.preferences.userRole == .student {
                    Section("Klasa i grupa") {
                        HStack {
                            Text("Wybrana klasa")
                            Spacer()
                            Text(viewModel.preferences.selectedClassName.isEmpty
                                 ? "Nie wybrano"
                                 : ScheduleFilterMatcher.extractPrimaryClassCode(viewModel.preferences.selectedClassName))
                                .foregroundStyle(.secondary)
                        }
                        Button("Wybierz / zmień klasę", action: onOpenClassPicker)

                        Picker("Grupa", selection: Binding(
                            get: { viewModel.preferences.selectedGroup },
                            set: { viewModel.updateGroup($0) }
                        )) {
                            ForEach(StudentGroup.allCases) { grp in
                                Text(grp.displayName).tag(grp)
                            }
                        }
                    }
                } else {
                    Section("Profil nauczyciela") {
                        TextField("Skrót nauczyciela (np. JK)", text: $teacherAbbrDraft)
                            .textInputAutocapitalization(.characters)
                        if !viewModel.catalog.teachers.isEmpty {
                            Menu("Wybierz skrót z listy (\(viewModel.catalog.teachers.count))") {
                                ForEach(viewModel.catalog.teachers) { teacher in
                                    Button(teacher.name) {
                                        teacherAbbrDraft = teacher.name
                                        viewModel.updatePreferences { $0.teacherAbbreviation = teacher.name.uppercased() }
                                        Task { await viewModel.refreshPrimaryTimetable() }
                                    }
                                }
                            }
                        } else {
                            Button("Wczytaj listę skrótów nauczycieli") {
                                Task { await viewModel.discoverTeachersIfNeeded() }
                            }
                        }
                        Button("Zapisz skrót i wyszukaj plan") {
                            viewModel.updatePreferences { $0.teacherAbbreviation = teacherAbbrDraft.trimmingCharacters(in: .whitespaces).uppercased() }
                            Task { await viewModel.refreshPrimaryTimetable() }
                        }
                    }
                }

                Section("Komunikator BLE Mesh") {
                    TextField("Twój nick w sieci BLE", text: $meshNickDraft)
                    Button("Zapisz nick") {
                        viewModel.updatePreferences { $0.meshNickname = meshNickDraft.trimmingCharacters(in: .whitespaces) }
                    }
                }

                Section("Powiadomienia o zastępstwach") {
                    Toggle("Powiadomienia w tle", isOn: Binding(
                        get: { viewModel.preferences.notificationsEnabled },
                        set: { enabled in
                            viewModel.updatePreferences { $0.notificationsEnabled = enabled }
                            if enabled {
                                Task {
                                    _ = await NotificationManager.shared.requestAuthorization()
                                    NotificationManager.shared.scheduleBackgroundRefresh(intervalMinutes: viewModel.preferences.checkIntervalMinutes)
                                }
                            }
                        }
                    ))
                    Stepper("Sprawdzaj co \(viewModel.preferences.checkIntervalMinutes) min",
                            value: Binding(
                                get: { viewModel.preferences.checkIntervalMinutes },
                                set: { val in viewModel.updatePreferences { $0.checkIntervalMinutes = val } }
                            ),
                            in: 15...120,
                            step: 15)
                }

                Section("Wygląd") {
                    Picker("Motyw", selection: Binding(
                        get: { viewModel.preferences.themeMode },
                        set: { mode in viewModel.updatePreferences { $0.themeMode = mode } }
                    )) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                Section("Adresy portali ZSME") {
                    TextField("URL planu lekcji", text: $planUrlDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("URL zastępstw", text: $subsUrlDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Klucz sekretariatu", text: $secKeyDraft)
                    Button("Zapisz adresy i odśwież") {
                        viewModel.updatePreferences {
                            $0.planUrl = planUrlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            $0.substitutionsUrl = subsUrlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            $0.secretariatKey = secKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        Task { await viewModel.refreshAll() }
                    }
                    Button("Przywróć domyślne adresy ZSME", role: .destructive) {
                        planUrlDraft = UserPreferences.defaultPlanUrl
                        subsUrlDraft = UserPreferences.defaultSubstitutionsUrl
                        secKeyDraft = UserPreferences.defaultSecretariatKey
                        viewModel.updatePreferences {
                            $0.planUrl = UserPreferences.defaultPlanUrl
                            $0.substitutionsUrl = UserPreferences.defaultSubstitutionsUrl
                            $0.secretariatKey = UserPreferences.defaultSecretariatKey
                        }
                    }
                }
            }
            .navigationTitle("Ustawienia")
            .onAppear {
                teacherAbbrDraft = viewModel.preferences.teacherAbbreviation
                planUrlDraft = viewModel.preferences.planUrl
                subsUrlDraft = viewModel.preferences.substitutionsUrl
                secKeyDraft = viewModel.preferences.secretariatKey
                meshNickDraft = viewModel.preferences.meshNickname
            }
            .alert("Dostęp dla nauczyciela", isPresented: $showTeacherPasswordAlert) {
                SecureField("Hasło dostępowe", text: $teacherPasswordInput)
                Button("Odblokuj") {
                    if UserPreferences.isValidTeacherAccessPassword(teacherPasswordInput) {
                        viewModel.updatePreferences { $0.userRole = .teacher }
                    } else {
                        teacherPasswordError = true
                    }
                }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Wpisz hasło dostępowe trybu nauczyciela.")
            }
            .alert("Nieprawidłowe hasło", isPresented: $teacherPasswordError) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}
