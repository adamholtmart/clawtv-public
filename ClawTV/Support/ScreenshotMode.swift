import Foundation

/// Test-only launch flag for capturing App Store screenshots without driving
/// the tvOS Simulator's remote. Activated by `-Screenshots <screen>` arg, where
/// `<screen>` is one of: welcome, attestation, playlist, epg, done, paywall,
/// home, guide, search, favorites, all, settings.
///
/// Active in DEBUG builds only — release builds ignore the flag entirely.
enum ScreenshotMode {
    enum Screen: String {
        case welcome, attestation, playlist, epg, done
        case paywall
        case home, guide, search, favorites, all, settings
    }

    static var isActive: Bool {
        #if DEBUG
        return screen != nil
        #else
        return false
        #endif
    }

    static var screen: Screen? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-Screenshots"), idx + 1 < args.count else { return nil }
        return Screen(rawValue: args[idx + 1])
        #else
        return nil
        #endif
    }

    /// True if the requested screen is part of the main shell (post-onboarding,
    /// post-paywall). Forces playlist seeding + paywall bypass.
    static var needsShell: Bool {
        guard let screen else { return false }
        switch screen {
        case .home, .guide, .search, .favorites, .all, .settings: return true
        default: return false
        }
    }

    /// Sample playlist URL used to seed channels for shell-mode screenshots.
    /// Public, trusted list maintained by the iptv-org community.
    static let sampleListURL = URL(string: "https://iptv-org.github.io/iptv/countries/us.m3u")!
}
