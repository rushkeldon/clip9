import SwiftUI
import ServiceManagement

private let log = LogService.shared

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("baseZoomLevel") private var baseZoomLevel = 1.0
    @AppStorage("historySize") private var historySize = 100
    @AppStorage("storageCapGB") private var storageCapGB = 5.0
    @State private var currentUsageBytes: Int = 0

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }

            Section("Appearance") {
                VStack(alignment: .leading) {
                    Text("Card Size: \(baseZoomLevel, specifier: "%.1f")x")
                    Slider(value: $baseZoomLevel, in: 0.5...3.0, step: 0.1) {
                        Text("Card Size")
                    }
                    Text("Also adjustable with \u{2318}+ / \u{2318}- / \u{2318}0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }

            Section("History") {
                Stepper("Max Items: \(historySize)", value: $historySize, in: 10...500, step: 10)

                VStack(alignment: .leading) {
                    Text("Storage Cap: \(storageCapGB, specifier: "%.1f") GB")
                    Slider(value: $storageCapGB, in: 0.5...20.0, step: 0.5) {
                        Text("Storage Cap")
                    }
                    Text("Current usage: \(formattedUsage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                Button("Show Logs") {
                    log.info("Settings", "User opened log folder", emoji: "📂")
                    LogService.shared.openLogsInFinder()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            currentUsageBytes = StorageManager.shared.currentStorageBytes
            log.info("Settings", "Settings view opened", emoji: "⚙️")
        }
    }

    private var formattedUsage: String {
        let bytes = currentUsageBytes
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else {
            return String(format: "%.0f MB", Double(bytes) / 1_048_576)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                log.info("Settings", "Launch at login enabled", emoji: "✅")
            } else {
                try SMAppService.mainApp.unregister()
                log.info("Settings", "Launch at login disabled", emoji: "🛑")
            }
        } catch {
            log.error("Settings", "Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}
