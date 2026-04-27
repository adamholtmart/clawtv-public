import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var epg: EPGService
    @EnvironmentObject var entitlement: EntitlementStore

    @State private var step: Step
    @State private var attestationConfirmed: Bool
    @State private var playlistName = ""
    @State private var playlistURL = ""
    @State private var epgURL = ""
    @State private var isAdding = false
    @State private var addError: String?

    enum Step { case welcome, attestation, playlist, epg, done }

    init(initialStep: Step = .welcome) {
        _step = State(initialValue: initialStep)
        // For screenshot mode: pre-tick attestation if we're past that step
        let preTicked: Bool
        switch initialStep {
        case .welcome, .attestation: preTicked = false
        default: preTicked = true
        }
        _attestationConfirmed = State(initialValue: preTicked)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.10),
                         Color(red: 0.10, green: 0.04, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Group {
                switch step {
                case .welcome:     welcomeStep
                case .attestation: attestationStep
                case .playlist:    playlistStep
                case .epg:         epgStep
                case .done:        doneStep
                }
            }
            .padding(.horizontal, 100)
            .frame(maxWidth: 1280)
        }
    }

    private var trialBadge: some View {
        Group {
            if entitlement.isInTrial {
                Text("Free trial — \(entitlement.trialDaysRemaining) day\(entitlement.trialDaysRemaining == 1 ? "" : "s") left")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 36) {
            Spacer()
            Image(systemName: "tv.fill")
                .font(.system(size: 110))
                .foregroundStyle(.tint)
            Text("Welcome to ClawTV")
                .font(.system(size: 80, weight: .heavy, design: .rounded))
            Text("A beautiful native player for your IPTV & M3U playlists.")
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            trialBadge
            Spacer()
            Button {
                step = .attestation
            } label: {
                Label("Get Started", systemImage: "arrow.right.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 480)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer().frame(height: 40)
        }
    }

    private var attestationStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Label("Before you continue", systemImage: "checkmark.shield.fill")
                .font(.largeTitle.bold())
            Text("ClawTV is a player. It does not provide, host, or sell any TV channels or content.")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 18) {
                bullet("You'll add your own M3U playlist URL — typically from your IPTV provider, your home media server, or a public source.")
                bullet("You are responsible for ensuring you have the rights to view any content you load into ClawTV.")
                bullet("Misuse of third-party streams may violate copyright law in your country.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                attestationConfirmed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: attestationConfirmed ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(attestationConfirmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text("I understand and confirm I have the right to view the content I'm about to load.")
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 6)
            }
            .padding(.top, 8)
            HStack(spacing: 18) {
                Button("Back") { step = .welcome }
                    .buttonStyle(.bordered)
                Button {
                    step = .playlist
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .frame(minWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!attestationConfirmed)
            }
            .padding(.top, 12)
            Spacer()
        }
    }

    private var playlistStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            HStack {
                Label("Add your playlist", systemImage: "list.bullet.rectangle.portrait")
                    .font(.largeTitle.bold())
                Spacer()
                trialBadge
            }
            Text("Paste the M3U URL provided by your IPTV service or media server.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text("Playlist Name (optional)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. My IPTV", text: $playlistName)
                    .textContentType(.name)

                Text("M3U URL")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                TextField("https://example.com/playlist.m3u", text: $playlistURL)
                    .textContentType(.URL)
            }

            if let err = addError {
                Text(err).font(.callout).foregroundStyle(.red)
            }

            HStack(spacing: 18) {
                Button("Back") { step = .attestation }
                    .buttonStyle(.bordered)
                    .disabled(isAdding)
                Button {
                    Task { await addPlaylist() }
                } label: {
                    HStack {
                        if isAdding { ProgressView() }
                        Label(isAdding ? "Adding…" : "Add Playlist",
                              systemImage: "plus.circle.fill")
                    }
                    .frame(minWidth: 320)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAdding || playlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private var epgStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Label("Add a program guide (optional)", systemImage: "calendar.day.timeline.left")
                .font(.largeTitle.bold())
            Text("If your provider offers an XMLTV / EPG URL, paste it here for the Guide tab. You can skip this and add it later in Settings.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text("XMLTV / EPG URL")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("https://example.com/epg.xml", text: $epgURL)
                    .textContentType(.URL)
            }

            HStack(spacing: 18) {
                Button("Skip") { step = .done }
                    .buttonStyle(.bordered)
                Button {
                    let trimmed = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        epg.epgURL = trimmed
                        Task { await epg.refresh() }
                    }
                    step = .done
                } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .frame(minWidth: 240)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private var doneStep: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 110))
                .foregroundStyle(.tint)
            Text("You're all set")
                .font(.system(size: 70, weight: .heavy, design: .rounded))
            Text("Loaded \(store.channels.count) channel\(store.channels.count == 1 ? "" : "s") from your playlist.")
                .font(.title3)
                .foregroundStyle(.secondary)
            trialBadge
            Spacer()
            Button {
                // RootView will switch to MainShellView automatically because
                // store.playlists is non-empty.
            } label: {
                Label("Start Watching", systemImage: "play.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 480)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer().frame(height: 40)
        }
    }

    // MARK: - Helpers

    private func addPlaylist() async {
        let trimmedURL = playlistURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), let scheme = url.scheme,
              scheme.lowercased() == "http" || scheme.lowercased() == "https" else {
            addError = "Please enter a valid http(s) URL."
            return
        }
        addError = nil
        isAdding = true
        await store.addPlaylist(name: playlistName.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
        isAdding = false
        if store.playlists.isEmpty {
            addError = "Couldn't load that playlist. Double-check the URL."
            return
        }
        step = .epg
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.tint)
                .padding(.top, 8)
            Text(text)
                .font(.title3)
        }
    }
}
