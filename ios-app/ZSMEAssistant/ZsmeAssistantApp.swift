import SwiftUI
import BackgroundTasks

@main
struct ZsmeAssistantApp: App {
    @StateObject private var viewModel = ZsmeViewModel()

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NotificationManager.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let bgClient = ZsmePortalClient()
            let opTask = Task {
                let prefsData = UserDefaults.standard.data(forKey: "zsme_user_preferences_v1")
                let prefs = prefsData.flatMap { try? JSONDecoder().decode(UserPreferences.self, from: $0) } ?? UserPreferences()
                if let snap = try? await bgClient.fetchSubstitutions(accessKey: prefs.secretariatKey, baseUrl: prefs.substitutionsUrl) {
                    if !snap.rawHash.isEmpty && snap.rawHash != prefs.lastNotifiedSubstitutionsHash && prefs.notificationsEnabled {
                        NotificationManager.shared.sendLocalNotification(
                            title: "Nowe zastępstwa ZSME",
                            body: "Sprawdź zaktualizowaną listę zastępstw na sekretariat.zsme.pl."
                        )
                    }
                }
                NotificationManager.shared.scheduleBackgroundRefresh(intervalMinutes: prefs.checkIntervalMinutes)
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                opTask.cancel()
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch viewModel.preferences.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(viewModel: viewModel)
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
