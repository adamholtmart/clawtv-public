import Foundation

extension Notification.Name {
    static let cloudSyncDidChange = Notification.Name("com.clawtv.cloudSyncDidChange")
}

/// Thin wrapper around NSUbiquitousKeyValueStore.
/// Every write goes to both iCloud KV and local UserDefaults.
/// Reads prefer iCloud; fall back to UserDefaults for keys not yet uploaded.
/// Fires .cloudSyncDidChange when the server pushes new values.
final class CloudSync {
    static let shared = CloudSync()

    private let icloud = NSUbiquitousKeyValueStore.default
    private let local  = UserDefaults.standard

    private init() {
        icloud.synchronize()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: icloud
        )
    }

    // MARK: - Write

    func set(_ value: Any?, forKey key: String) {
        local.set(value, forKey: key)
        icloud.set(value, forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        local.set(value, forKey: key)
        icloud.set(value, forKey: key)
    }

    func removeObject(forKey key: String) {
        local.removeObject(forKey: key)
        icloud.removeObject(forKey: key)
    }

    // MARK: - Read (iCloud first, UserDefaults fallback)

    func data(forKey key: String) -> Data? {
        icloud.data(forKey: key) ?? local.data(forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        icloud.object(forKey: key) != nil ? icloud.bool(forKey: key) : local.bool(forKey: key)
    }

    func string(forKey key: String) -> String? {
        icloud.string(forKey: key) ?? local.string(forKey: key)
    }

    // MARK: - External change from server

    @objc private func externalChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reason = info[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange
        else { return }

        let changed = info[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

        // Mirror each changed iCloud value down to UserDefaults
        for key in changed {
            if let data = icloud.data(forKey: key) {
                local.set(data, forKey: key)
            } else if let str = icloud.string(forKey: key) {
                local.set(str, forKey: key)
            } else if let obj = icloud.object(forKey: key) {
                local.set(obj, forKey: key)
            } else {
                local.removeObject(forKey: key)
            }
        }

        NotificationCenter.default.post(
            name: .cloudSyncDidChange,
            object: nil,
            userInfo: ["changedKeys": changed]
        )
    }
}
