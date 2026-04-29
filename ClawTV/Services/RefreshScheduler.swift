import Foundation
import SwiftUI
import Combine

/// Schedules periodic playlist + EPG refreshes while the app is in the
/// foreground. tvOS has no background-task scheduler, so this is a foreground
/// timer that calls `refreshIfStale` on both stores once per minute.
///
/// User picks the cadence in Settings: 6h / 12h / 24h / 48h / manual.
@MainActor
final class RefreshScheduler: ObservableObject {
    enum Interval: String, CaseIterable, Identifiable, Codable {
        case manual = "manual"
        case sixHours = "6h"
        case twelveHours = "12h"
        case daily = "24h"
        case twoDays = "48h"

        var id: String { rawValue }

        var seconds: TimeInterval? {
            switch self {
            case .manual: return nil
            case .sixHours: return 6 * 3600
            case .twelveHours: return 12 * 3600
            case .daily: return 24 * 3600
            case .twoDays: return 48 * 3600
            }
        }

        var label: String {
            switch self {
            case .manual: return "Manual"
            case .sixHours: return "Every 6 hours"
            case .twelveHours: return "Every 12 hours"
            case .daily: return "Every 24 hours"
            case .twoDays: return "Every 2 days"
            }
        }
    }

    @Published var interval: Interval {
        didSet {
            UserDefaults.standard.set(interval.rawValue, forKey: intervalKey)
            CloudSync.shared.setString(interval.rawValue, for: intervalKey)
        }
    }

    @Published private(set) var lastAutoRun: Date?

    private let intervalKey = "clawtv.refresh.interval.v1"
    private weak var store: PlaylistStore?
    private weak var epg: EPGService?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let raw = CloudSync.shared.string(for: intervalKey)
            ?? UserDefaults.standard.string(forKey: intervalKey)
            ?? Interval.daily.rawValue
        self.interval = Interval(rawValue: raw) ?? .daily

        CloudSync.shared.externalChange
            .sink { [weak self] keys in
                guard let self else { return }
                Task { @MainActor in
                    if keys.contains(self.intervalKey),
                       let raw = CloudSync.shared.string(for: self.intervalKey),
                       let v = Interval(rawValue: raw),
                       v != self.interval {
                        self.interval = v
                    }
                }
            }
            .store(in: &cancellables)
    }

    func bind(store: PlaylistStore, epg: EPGService) {
        self.store = store
        self.epg = epg
        startTimer()
    }

    /// Returns a stream URL with catchup template variables expanded for
    /// playing back a programme that aired in the past.
    static func catchupURL(template: String,
                           start: Date,
                           duration: TimeInterval) -> URL? {
        let startSec = Int(start.timeIntervalSince1970)
        let durSec = Int(duration)
        let endSec = startSec + durSec
        let expanded = template
            .replacingOccurrences(of: "${start}", with: String(startSec))
            .replacingOccurrences(of: "${duration}", with: String(durSec))
            .replacingOccurrences(of: "${end}", with: String(endSec))
            .replacingOccurrences(of: "{Y}", with: yearString(start))
            .replacingOccurrences(of: "{m}", with: monthString(start))
            .replacingOccurrences(of: "{d}", with: dayString(start))
            .replacingOccurrences(of: "{H}", with: hourString(start))
            .replacingOccurrences(of: "{M}", with: minuteString(start))
        return URL(string: expanded)
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func yearString(_ d: Date) -> String {
        String(format: "%04d", utcCalendar.component(.year, from: d))
    }
    private static func monthString(_ d: Date) -> String {
        String(format: "%02d", utcCalendar.component(.month, from: d))
    }
    private static func dayString(_ d: Date) -> String {
        String(format: "%02d", utcCalendar.component(.day, from: d))
    }
    private static func hourString(_ d: Date) -> String {
        String(format: "%02d", utcCalendar.component(.hour, from: d))
    }
    private static func minuteString(_ d: Date) -> String {
        String(format: "%02d", utcCalendar.component(.minute, from: d))
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let seconds = interval.seconds else { return }
        let lastStore = store?.lastRefresh
        let lastEPG = epg?.lastRefresh
        let now = Date()

        if let store, lastStore == nil || now.timeIntervalSince(lastStore!) >= seconds {
            Task { await store.refresh() }
            lastAutoRun = now
        }
        if let epg, !epg.epgURL.isEmpty,
           lastEPG == nil || now.timeIntervalSince(lastEPG!) >= seconds {
            Task { await epg.refresh() }
            lastAutoRun = now
        }
    }
}
