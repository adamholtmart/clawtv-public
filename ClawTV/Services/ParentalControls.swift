import Foundation
import SwiftUI
import Combine
import CryptoKit

/// Parental PIN + locked category/channel set. PIN is stored as a SHA256 hash
/// (never plaintext). Lock state syncs across devices via iCloud KVS.
///
/// Unlock is per-session: tapping into a locked category prompts for the PIN,
/// and the unlock holds until the app process is restarted.
@MainActor
final class ParentalControls: ObservableObject {
    @Published private(set) var pinHash: String?
    @Published private(set) var lockedGroups: Set<String> = []
    @Published private(set) var lockedChannels: Set<String> = []

    /// Categories/channels the user has unlocked this session by entering the PIN.
    @Published private(set) var sessionUnlockedGroups: Set<String> = []
    @Published private(set) var sessionUnlockedChannels: Set<String> = []

    private let pinKey = "clawtv.parental.pinHash.v1"
    private let lockedGroupsKey = "clawtv.parental.lockedGroups.v1"
    private let lockedChannelsKey = "clawtv.parental.lockedChannels.v1"
    private var cancellables: Set<AnyCancellable> = []

    var isPINSet: Bool { pinHash != nil }

    init() {
        load()
        observeCloud()
    }

    // MARK: - Lock checks

    func isLocked(group: String) -> Bool {
        guard isPINSet else { return false }
        return lockedGroups.contains(group) && !sessionUnlockedGroups.contains(group)
    }

    func isLocked(channel: Channel) -> Bool {
        guard isPINSet else { return false }
        if sessionUnlockedChannels.contains(channel.id) { return false }
        if lockedChannels.contains(channel.id) { return true }
        if lockedGroups.contains(channel.groupTitle) && !sessionUnlockedGroups.contains(channel.groupTitle) {
            return true
        }
        return false
    }

    // MARK: - PIN management

    func setPIN(_ pin: String) {
        let hash = Self.hash(pin)
        pinHash = hash
        UserDefaults.standard.set(hash, forKey: pinKey)
        CloudSync.shared.setString(hash, for: pinKey)
    }

    func removePIN() {
        pinHash = nil
        lockedGroups = []
        lockedChannels = []
        sessionUnlockedGroups = []
        sessionUnlockedChannels = []
        UserDefaults.standard.removeObject(forKey: pinKey)
        UserDefaults.standard.removeObject(forKey: lockedGroupsKey)
        UserDefaults.standard.removeObject(forKey: lockedChannelsKey)
        CloudSync.shared.setString(nil, for: pinKey)
        CloudSync.shared.set(nil, for: lockedGroupsKey)
        CloudSync.shared.set(nil, for: lockedChannelsKey)
    }

    func verify(_ pin: String) -> Bool {
        guard let pinHash else { return true }
        return Self.hash(pin) == pinHash
    }

    // MARK: - Lock toggles

    func toggleLock(group: String) {
        if lockedGroups.contains(group) {
            lockedGroups.remove(group)
        } else {
            lockedGroups.insert(group)
        }
        persistGroups()
    }

    func toggleLock(channel: Channel) {
        if lockedChannels.contains(channel.id) {
            lockedChannels.remove(channel.id)
        } else {
            lockedChannels.insert(channel.id)
        }
        persistChannels()
    }

    // MARK: - Session unlocks

    func unlockSession(group: String) {
        sessionUnlockedGroups.insert(group)
    }

    func unlockSession(channel: Channel) {
        sessionUnlockedChannels.insert(channel.id)
        sessionUnlockedGroups.insert(channel.groupTitle)
    }

    func relockSession() {
        sessionUnlockedGroups = []
        sessionUnlockedChannels = []
    }

    // MARK: - Persistence

    private func load() {
        pinHash = CloudSync.shared.string(for: pinKey)
            ?? UserDefaults.standard.string(forKey: pinKey)
        if let data = CloudSync.shared.data(for: lockedGroupsKey)
            ?? UserDefaults.standard.data(forKey: lockedGroupsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            lockedGroups = decoded
        }
        if let data = CloudSync.shared.data(for: lockedChannelsKey)
            ?? UserDefaults.standard.data(forKey: lockedChannelsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            lockedChannels = decoded
        }
    }

    private func persistGroups() {
        if let data = try? JSONEncoder().encode(lockedGroups) {
            UserDefaults.standard.set(data, forKey: lockedGroupsKey)
            CloudSync.shared.set(data, for: lockedGroupsKey)
        }
    }

    private func persistChannels() {
        if let data = try? JSONEncoder().encode(lockedChannels) {
            UserDefaults.standard.set(data, forKey: lockedChannelsKey)
            CloudSync.shared.set(data, for: lockedChannelsKey)
        }
    }

    private func observeCloud() {
        CloudSync.shared.externalChange
            .sink { [weak self] keys in
                guard let self else { return }
                Task { @MainActor in self.reloadFromCloud(keys) }
            }
            .store(in: &cancellables)
    }

    private func reloadFromCloud(_ keys: Set<String>) {
        if keys.contains(pinKey) {
            pinHash = CloudSync.shared.string(for: pinKey)
        }
        if keys.contains(lockedGroupsKey),
           let data = CloudSync.shared.data(for: lockedGroupsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            lockedGroups = decoded
        }
        if keys.contains(lockedChannelsKey),
           let data = CloudSync.shared.data(for: lockedChannelsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            lockedChannels = decoded
        }
    }

    private static func hash(_ pin: String) -> String {
        let data = Data(pin.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
