import Foundation
import ZenTouchCore

/// Holds the panel's settings. Edits apply to the driver immediately (so you can try them with your
/// fingers) but are only written to disk on `save()`; `discard()` goes back to the last saved state.
final class SettingsStore: ObservableObject {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ZenTouch/settings.json")

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            onChange?(settings)
        }
    }

    /// What's on disk.
    @Published private(set) var saved: Settings

    var hasUnsavedChanges: Bool { settings != saved }

    var onChange: ((Settings) -> Void)?

    init() {
        let loaded = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        settings = loaded ?? Settings()
        saved = loaded ?? Settings()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Self.fileURL, options: .atomic)
            saved = settings
        } catch {
            print("[zentouch] Couldn't save settings: \(error)")
        }
    }

    func discard() {
        settings = saved
    }
}
