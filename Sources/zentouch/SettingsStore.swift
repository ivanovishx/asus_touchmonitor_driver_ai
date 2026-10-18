import Foundation
import ZenTouchCore

/// Loads and saves the panel's settings, and tells the driver when they change.
final class SettingsStore: ObservableObject {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ZenTouch/settings.json")

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
            onChange?(settings)
        }
    }

    var onChange: ((Settings) -> Void)?

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        } else {
            settings = Settings()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[zentouch] Couldn't save settings: \(error)")
        }
    }
}
