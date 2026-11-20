import SwiftUI

enum ZsmeTheme {
    static let cobalt = Color(red: 15 / 255, green: 76 / 255, blue: 129 / 255)
    static let teal = Color(red: 0 / 255, green: 121 / 255, blue: 140 / 255)
    static let amber = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    static let liveGreen = Color(red: 15 / 255, green: 138 / 255, blue: 95 / 255)
    static let crimson = Color(red: 186 / 255, green: 26 / 255, blue: 26 / 255)

    static let backgroundLight = Color(red: 244 / 255, green: 247 / 255, blue: 251 / 255)
    static let backgroundDark = Color(red: 10 / 255, green: 17 / 255, blue: 26 / 255)
    static let surfaceLight = Color.white
    static let surfaceDark = Color(red: 18 / 255, green: 28 / 255, blue: 41 / 255)

    static func schoolAccent(for index: Int) -> Color {
        let palette = [cobalt, liveGreen, amber, Color.purple, Color.pink, teal]
        let safe = ((index % palette.count) + palette.count) % palette.count
        return palette[safe]
    }
}

struct ClassPickerSheet: View {
    @ObservedObject var viewModel: ZsmeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var filteredClasses: [SchoolClass] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return viewModel.catalog.classes }
        return viewModel.catalog.classes.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let catErr = viewModel.catalogError, viewModel.catalog.classes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(catErr, systemImage: "wifi.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(ZsmeTheme.crimson)
                        Button("Spróbuj ponownie") {
                            Task { await viewModel.refreshCatalog(silent: false) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ZsmeTheme.cobalt)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                } else if viewModel.isRefreshingCatalog && viewModel.catalog.classes.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Pobieranie listy klas z plan.zsme.pl...")
                            .foregroundStyle(.secondary)
                    }
                } else if filteredClasses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Brak pasujących klas. Odśwież katalog lub sprawdź połączenie.")
                            .foregroundStyle(.secondary)
                        Button("Odśwież katalog") {
                            Task { await viewModel.refreshCatalog(silent: false) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                } else {
                    ForEach(filteredClasses) { cls in
                        Button {
                            viewModel.selectClass(cls)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ScheduleFilterMatcher.extractPrimaryClassCode(cls.name))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(cls.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if cls.name == viewModel.preferences.selectedClassName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(ZsmeTheme.cobalt)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Szukaj klasy (np. 3TA, 2TB)...")
            .navigationTitle("Wybierz klasę")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.refreshCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}
