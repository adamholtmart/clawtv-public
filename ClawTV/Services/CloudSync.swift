import Foundation
import SwiftUI
import Combine

/// iCloud Key-Value Store wrapper. Mirrors a small set of user settings
/// (playlists, Xtream creds, EPG URL, favorites, parental controls, etc.)
/// across all of a user's Apple TVs signed into the same iCloud account.
///
/// Storage limit is 1 MB / 1024 keys — far above what we use. We never
/// sync the M3U playlist *contents* (those re-fetch from the URL on each
/// device), only the small config that lets a fresh install bootstrap.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    /// User-facing toggle. Defaults ON for new installs.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    /// Fires when the iCloud store changes externally (another device wrote).
    /// Subscribers reload their local state from `CloudSync` keys.
    let externalChange = PassthroughSubject<Set<String>, Never>()

    private let enabledKey = "clawtv.cloudSync.enabled.v1"
    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    private init() {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
        self.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleExternalChange(note) }
        }
        store.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Read

    func data(for key: String) -> Data? {
        guard isEnabled else { return nil }
        return store.data(forKey: key)
    }

    func string(for key: String) -> String? {
        guard isEnabled else { return nil }
        return store.string(forKey: key)
    }

    func bool(for key: String) -> Bool? {
        guard isEnabled, store.object(forKey: key) != nil else { return nil }
        return store.bool(forKey: key)
    }

    // MARK: - Write

    func set(_ value: Data?, for key: String) {
        guard isEnabled else { return }
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
        store.synchronize()
    }

    func setString(_ value: String?, for key: String) {
        guard isEnabled else { return }
        if let value, !value.isEmpty {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
        store.synchronize()
    }

    func setBool(_ value: Bool, for key: String) {
        guard isEnabled else { return }
        store.set(value, forKey: key)
        store.synchronize()
    }

    // MARK: - Internal

    private func handleExternalChange(_ note: Notification) {
        guard isEnabled else { return }
        let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
        externalChange.send(Set(keys))
    }
}
