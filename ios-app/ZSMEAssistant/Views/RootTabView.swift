import SwiftUI

enum ZsmeTab: Hashable {
    case home
    case substitutions
    case timetable
    case messenger
    case settings
}

struct RootTabView: View {
    @ObservedObject var viewModel: ZsmeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab: ZsmeTab = .home
    @State private var showClassPicker = false

    var body: some View {
        TabView(selection: $activeTab) {
            HomeView(
                viewModel: viewModel,
                onOpenClassPicker: { showClassPicker = true },
                onOpenTimetable: { activeTab = .timetable },
                onOpenSubstitutions: { activeTab = .substitutions },
                onOpenSettings: { activeTab = .settings }
            )
            .tabItem {
                Label("Główna", systemImage: "house.fill")
            }
            .tag(ZsmeTab.home)

            SubstitutionsView(
                viewModel: viewModel,
                onOpenClassPicker: { showClassPicker = true }
            )
            .tabItem {
                Label("Zastępstwa", systemImage: "arrow.triangle.2.circlepath")
            }
            .badge(viewModel.myGroupSubstitutions.count)
            .tag(ZsmeTab.substitutions)

            TimetableView(
                viewModel: viewModel,
                onOpenClassPicker: { showClassPicker = true }
            )
            .tabItem {
                Label("Plan lekcji", systemImage: "calendar")
            }
            .tag(ZsmeTab.timetable)

            MessengerView(
                viewModel: viewModel,
                mesh: viewModel.meshManager
            )
            .tabItem {
                Label("Komunikator", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tag(ZsmeTab.messenger)

            SettingsView(
                viewModel: viewModel,
                onOpenClassPicker: { showClassPicker = true }
            )
            .tabItem {
                Label("Ustawienia", systemImage: "gearshape.fill")
            }
            .tag(ZsmeTab.settings)
        }
        .tint(ZsmeTheme.cobalt)
        .sheet(isPresented: $showClassPicker) {
            ClassPickerSheet(viewModel: viewModel)
        }
        .alert("Uwaga", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.rebuildPreparedSchedule()
            }
        }
    }
}
