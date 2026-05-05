import SwiftUI
#if os(tvOS)
import TVVLCKit
#else
import AVKit
#endif

struct SubtitleTrack: Identifiable, Equatable {
    let id: Int
    let name: String
}

struct PlayerView: View {
    let initialChannel: Channel
    let siblings: [Channel]
    let origin: PlaybackOrigin
    let initialEPGChannelId: String?
    let onSelectTab: (MainTab) -> Void
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var epg: EPGService
    @Environment(\.dismiss) private var dismiss

    @State private var currentChannel: Channel
    @State private var status: PlayerStatus = .loading
    @State private var errorText: String?
    @State private var hintVisible = true
    @State private var hasStartedPlaying = false
    @State private var showCCPicker = false
    @State private var showInfoOverlay = false
    @State private var subtitleTracks: [SubtitleTrack] = []
    @State private var activeSubtitleID: Int = -1
    @State private var infoHideTask: Task<Void, Never>?
    #if os(tvOS)
    @FocusState private var playerFocused: Bool
    #endif

    init(channel: Channel,
         siblings: [Channel] = [],
         origin: PlaybackOrigin = .standalone,
         epgChannelId: String? = nil,
         onSelectTab: @escaping (MainTab) -> Void = { _ in }) {
        self.initialChannel = channel
        self.siblings = siblings
        self.origin = origin
        self.initialEPGChannelId = epgChannelId
        self.onSelectTab = onSelectTab
        self._currentChannel = State(initialValue: channel)
    }

    /// EPG id associated with `currentChannel`. If the user swipes to another
    /// channel the initial association no longer applies.
    private var activeEPGChannelId: String? {
        guard let id = initialEPGChannelId,
              currentChannel.id == initialChannel.id else { return nil }
        return id
    }

    private var currentInfoNow: EPGProgramme? {
        if let id = activeEPGChannelId {
            return epg.currentProgramme(epgId: id)
        }
        return epg.currentProgramme(for: currentChannel)
    }

    private var currentInfoUpcoming: [EPGProgramme] {
        if let id = activeEPGChannelId {
            return epg.upcoming(epgId: id, limit: 3)
        }
        return epg.upcoming(for: currentChannel, limit: 3)
    }

    private var navigableList: [Channel] {
        siblings.isEmpty ? [currentChannel] : siblings
    }

    private var currentIndex: Int? {
        navigableList.firstIndex(where: { $0.id == currentChannel.id })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCPlayerView(
                url: currentChannel.streamURL,
                status: $status,
                errorText: $errorText,
                subtitleTracks: $subtitleTracks,
                activeSubtitleID: $activeSubtitleID
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    if hintVisible {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.uturn.backward")
                                Text(origin == .fromMultiView ? "Press Menu for Multi-View" : "Press Menu to Exit")
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "rectangle.split.2x2")
                                Text("Hold Select for Multi-View")
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "captions.bubble")
                                Text("Play/Pause for Subtitles")
                            }
                            if siblings.count > 1 {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.left.arrow.right")
                                    Text("Swipe L/R for Channel")
                                }
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle")
                                Text("Tap for Info")
                            }
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.55), in: .rect(cornerRadius: 14))
                        .transition(.opacity)
                    }
                }
                Spacer()
                if status == .error {
                    Button("Close") { dismiss() }
                        .padding(.bottom, 60)
                }
            }
            .padding(40)

            if status == .error {
                VStack(spacing: 12) {
                    Text("Stream failed")
                        .font(.title2).bold()
                    Text(errorText ?? "Unknown error")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .background(.black.opacity(0.6), in: .rect(cornerRadius: 16))
            }

            if status == .loading || status == .buffering {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(status == .loading ? "Starting…" : "Buffering…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: .capsule)
                    }
                    Spacer()
                }
                .padding(.top, hintVisible ? 220 : 40)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .transition(.opacity)
            }

            if showInfoOverlay {
                InfoOverlay(
                    channel: currentChannel,
                    now: currentInfoNow,
                    upcoming: currentInfoUpcoming,
                    position: positionLabel()
                )
                .transition(.opacity)
                .zIndex(5)
                .allowsHitTesting(false)
            }

            if showCCPicker {
                SubtitlePickerOverlay(
                    tracks: subtitleTracks,
                    activeID: $activeSubtitleID,
                    dismiss: { showCCPicker = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }

        }
        #if os(tvOS)
        .focusable(true)
        .focused($playerFocused)
        #endif
        .onAppear {
            #if os(tvOS)
            playerFocused = true
            #endif
            store.recordWatched(currentChannel)
            showInfoOverlay = true
            scheduleInfoHide()
        }
        .onTapGesture {
            toggleInfo()
        }
        .onLongPressGesture(minimumDuration: 0.7) {
            store.startMultiView(with: currentChannel)
        }
        #if os(tvOS)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            default: break
            }
        }
        .onPlayPauseCommand {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCCPicker.toggle()
            }
        }
        #endif
        .onChange(of: status) { _, newValue in
            if newValue == .playing && !hasStartedPlaying {
                hasStartedPlaying = true
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.easeOut(duration: 0.4)) { hintVisible = false }
                }
            } else if newValue == .error {
                withAnimation { hintVisible = true }
            }
        }
        .onChange(of: currentChannel.id) { _, _ in
            status = .loading
            errorText = nil
            hasStartedPlaying = false
            subtitleTracks = []
            activeSubtitleID = -1
            store.recordWatched(currentChannel)
            showInfoOverlay = true
            scheduleInfoHide()
        }
        #if os(tvOS)
        .onExitCommand {
            if showCCPicker {
                withAnimation { showCCPicker = false }
            } else if showInfoOverlay {
                withAnimation { showInfoOverlay = false }
                infoHideTask?.cancel()
            } else if origin == .fromMultiView {
                store.returnToMultiView()
            } else {
                dismiss()
            }
        }
        #endif
    }

    private func step(_ offset: Int) {
        guard siblings.count > 1, let idx = currentIndex else { return }
        let count = navigableList.count
        let next = ((idx + offset) % count + count) % count
        withAnimation(.easeInOut(duration: 0.15)) {
            currentChannel = navigableList[next]
        }
    }

    private func positionLabel() -> String? {
        guard siblings.count > 1, let idx = currentIndex else { return nil }
        return "\(idx + 1) of \(navigableList.count)"
    }

    private func toggleInfo() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showInfoOverlay.toggle()
        }
        if showInfoOverlay {
            scheduleInfoHide()
        } else {
            infoHideTask?.cancel()
        }
    }

    private func scheduleInfoHide() {
        infoHideTask?.cancel()
        infoHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) { showInfoOverlay = false }
            }
        }
    }
}

struct InfoOverlay: View {
    let channel: Channel
    let now: EPGProgramme?
    let upcoming: [EPGProgramme]
    let position: String?

    private var nextProg: EPGProgramme? {
        upcoming.first(where: { $0.start > (now?.stop ?? Date()) })
    }

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(channel.name)
                            .font(.system(size: 34, weight: .bold))
                        if let pos = position {
                            Text(pos)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.15), in: .capsule)
                        }
                    }
                    Text(channel.groupTitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))

                    if let now = now {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("NOW")
                                    .font(.caption.bold())
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.yellow, in: .capsule)
                                Text(now.title)
                                    .font(.title3.weight(.semibold))
                            }
                            Text(timeRange(now.start, now.stop))
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.top, 8)
                    }

                    if let next = nextProg {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("NEXT")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.2), in: .capsule)
                                Text(next.title)
                                    .font(.title3)
                            }
                            Text(timeRange(next.start, next.stop))
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer()
            }
            .padding(40)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }

    private func timeRange(_ start: Date, _ stop: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: stop))"
    }
}

struct SubtitlePickerOverlay: View {
    let tracks: [SubtitleTrack]
    @Binding var activeID: Int
    let dismiss: () -> Void

    private var displayTracks: [SubtitleTrack] {
        tracks.filter { $0.id >= 0 }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()

            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "captions.bubble")
                    Text("Subtitles / CC")
                }
                .font(.title2.bold())

                if displayTracks.isEmpty {
                    VStack(spacing: 8) {
                        Text("No subtitle tracks detected")
                            .foregroundStyle(.secondary)
                        Text("This stream may not include captions, or they haven't been parsed yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 520)
                } else {
                    VStack(spacing: 10) {
                        TrackRow(
                            label: "Off",
                            isActive: activeID == -1,
                            action: {
                                activeID = -1
                                dismiss()
                            }
                        )
                        ForEach(displayTracks) { track in
                            TrackRow(
                                label: track.name.isEmpty ? "Track \(track.id)" : track.name,
                                isActive: activeID == track.id,
                                action: {
                                    activeID = track.id
                                    dismiss()
                                }
                            )
                        }
                    }
                }

                Button("Close") { dismiss() }
                    .padding(.top, 8)
            }
            .padding(40)
            .frame(minWidth: 560)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
            .shadow(radius: 30)
        }
    }

    private struct TrackRow: View {
        let label: String
        let isActive: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    Text(label)
                        .font(.body)
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(minWidth: 460)
            }
        }
    }
}

enum PlayerStatus {
    case loading, buffering, playing, error
}

#if os(tvOS)
struct VLCPlayerView: UIViewRepresentable {
    let url: URL
    @Binding var status: PlayerStatus
    @Binding var errorText: String?
    @Binding var subtitleTracks: [SubtitleTrack]
    @Binding var activeSubtitleID: Int
    var muted: Bool = false
    var paused: Bool = false

    init(
        url: URL,
        status: Binding<PlayerStatus>,
        errorText: Binding<String?>,
        subtitleTracks: Binding<[SubtitleTrack]> = .constant([]),
        activeSubtitleID: Binding<Int> = .constant(-1),
        muted: Bool = false,
        paused: Bool = false
    ) {
        self.url = url
        self._status = status
        self._errorText = errorText
        self._subtitleTracks = subtitleTracks
        self._activeSubtitleID = activeSubtitleID
        self.muted = muted
        self.paused = paused
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.isUserInteractionEnabled = false

        let player = VLCMediaPlayer(options: [
            "--network-caching=5000",
            "--live-caching=5000",
            "--file-caching=5000",
            "--clock-jitter=0",
            "--clock-synchro=0",
            "--avcodec-hw=any",
            "--avcodec-fast",
            "--avcodec-skiploopfilter=4",
            "--http-reconnect",
            "--http-continuous",
            "--ts-seek-percent",
            "--no-audio-time-stretch"
        ])
        player.drawable = container
        player.delegate = context.coordinator
        context.coordinator.player = player
        context.coordinator.url = url

        loadMedia(into: player, url: url)
        player.audio?.isMuted = muted
        player.play()
        context.coordinator.startStallWatchdog()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = context.coordinator.player else { return }
        if context.coordinator.url != url {
            context.coordinator.url = url
            context.coordinator.resetStats()
            player.stop()
            loadMedia(into: player, url: url)
            player.play()
        }
        player.audio?.isMuted = muted
        if paused, player.isPlaying {
            player.pause()
        } else if !paused, !player.isPlaying {
            player.play()
        }
        if context.coordinator.lastAppliedSubtitleID != activeSubtitleID {
            player.currentVideoSubTitleIndex = Int32(activeSubtitleID)
            context.coordinator.lastAppliedSubtitleID = activeSubtitleID
        }
    }

    private func loadMedia(into player: VLCMediaPlayer, url: URL) {
        let media = VLCMedia(url: url)
        media.addOptions([
            "network-caching": 5000,
            "live-caching": 5000,
            "http-reconnect": true,
            "http-continuous": true
        ])
        player.media = media
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopStallWatchdog()
        coordinator.player?.stop()
        coordinator.player = nil
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        let parent: VLCPlayerView
        var player: VLCMediaPlayer?
        var url: URL?
        var lastAppliedSubtitleID: Int = -1
        private var watchdog: Timer?
        private var lastPosition: Float = -1
        private var stallTicks = 0
        private var retryCount = 0
        private var lastTrackSignature: String = ""

        init(_ parent: VLCPlayerView) { self.parent = parent }

        func resetStats() {
            lastPosition = -1
            stallTicks = 0
            retryCount = 0
            lastTrackSignature = ""
            lastAppliedSubtitleID = -1
        }

        func startStallWatchdog() {
            stopStallWatchdog()
            watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }

        func stopStallWatchdog() {
            watchdog?.invalidate()
            watchdog = nil
        }

        private func tick() {
            guard let player = player, let url = url else { return }
            let pos = player.position
            if player.state == .playing {
                if pos == lastPosition {
                    stallTicks += 1
                } else {
                    stallTicks = 0
                    retryCount = 0
                }
                lastPosition = pos
            }
            if stallTicks >= 3 && retryCount < 3 {
                stallTicks = 0
                retryCount += 1
                let media = VLCMedia(url: url)
                media.addOptions([
                    "network-caching": 5000,
                    "live-caching": 5000,
                    "http-reconnect": true,
                    "http-continuous": true
                ])
                player.media = media
                player.play()
            }
            refreshSubtitleTracks()
        }

        private func refreshSubtitleTracks() {
            guard let player = player else { return }
            var tracks: [SubtitleTrack] = []
            let indexes = (player.videoSubTitlesIndexes as? [NSNumber]) ?? []
            let names = (player.videoSubTitlesNames as? [NSString]) ?? []
            for i in 0..<min(indexes.count, names.count) {
                let id = indexes[i].intValue
                let raw = names[i] as String
                let name: String
                if id < 0 {
                    name = "Off"
                } else if raw.isEmpty || raw.lowercased() == "disable" {
                    name = "Track \(id)"
                } else {
                    name = raw
                }
                tracks.append(SubtitleTrack(id: id, name: name))
            }
            let sig = tracks.map { "\($0.id):\($0.name)" }.joined(separator: "|")
            guard sig != lastTrackSignature else { return }
            lastTrackSignature = sig
            DispatchQueue.main.async { [weak self] in
                self?.parent.subtitleTracks = tracks
            }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player = player else { return }
            DispatchQueue.main.async {
                switch player.state {
                case .opening, .esAdded:
                    self.parent.status = .loading
                case .buffering:
                    self.parent.status = player.isPlaying ? .playing : .buffering
                case .playing:
                    self.parent.status = .playing
                    self.parent.errorText = nil
                    self.retryCount = 0
                case .error:
                    self.parent.status = .error
                    self.parent.errorText = "VLC reported an error opening this stream."
                case .ended, .stopped:
                    if self.parent.status != .error {
                        self.parent.status = .error
                        self.parent.errorText = "Stream ended or was unreachable."
                    }
                case .paused:
                    break
                @unknown default:
                    break
                }
                self.refreshSubtitleTracks()
            }
        }
    }
}

#else // iOS

struct VLCPlayerView: UIViewRepresentable {
    let url: URL
    @Binding var status: PlayerStatus
    @Binding var errorText: String?
    @Binding var subtitleTracks: [SubtitleTrack]
    @Binding var activeSubtitleID: Int
    var muted: Bool = false
    var paused: Bool = false

    init(
        url: URL,
        status: Binding<PlayerStatus>,
        errorText: Binding<String?>,
        subtitleTracks: Binding<[SubtitleTrack]> = .constant([]),
        activeSubtitleID: Binding<Int> = .constant(-1),
        muted: Bool = false,
        paused: Bool = false
    ) {
        self.url = url
        self._status = status
        self._errorText = errorText
        self._subtitleTracks = subtitleTracks
        self._activeSubtitleID = activeSubtitleID
        self.muted = muted
        self.paused = paused
    }

    func makeUIView(context: Context) -> AVPlayerHostView {
        let hostView = AVPlayerHostView()
        hostView.backgroundColor = .black
        let player = AVPlayer(url: url)
        hostView.player = player
        context.coordinator.attach(player: player, to: hostView, binding: $status, errorBinding: $errorText)
        player.isMuted = muted
        if !paused { player.play() }
        return hostView
    }

    func updateUIView(_ uiView: AVPlayerHostView, context: Context) {
        let coord = context.coordinator

        if coord.currentURL != url {
            coord.currentURL = url
            let player = AVPlayer(url: url)
            uiView.player = player
            coord.attach(player: player, to: uiView, binding: $status, errorBinding: $errorText)
            player.isMuted = muted
            if !paused { player.play() }
            return
        }

        uiView.player?.isMuted = muted
        if paused {
            uiView.player?.pause()
        } else if uiView.player?.timeControlStatus == .paused {
            uiView.player?.play()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var currentURL: URL?
        private var statusObservation: NSKeyValueObservation?
        private var rateObservation: NSKeyValueObservation?
        private var errorObservation: NSKeyValueObservation?
        private var itemObservation: NSKeyValueObservation?

        func attach(player: AVPlayer, to view: AVPlayerHostView, binding: Binding<PlayerStatus>, errorBinding: Binding<String?>) {
            currentURL = (player.currentItem?.asset as? AVURLAsset)?.url
            statusObservation?.invalidate()
            rateObservation?.invalidate()
            errorObservation?.invalidate()
            itemObservation?.invalidate()

            binding.wrappedValue = .loading

            itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
                self?.observeItem(player: player, statusBinding: binding, errorBinding: errorBinding)
            }
            observeItem(player: player, statusBinding: binding, errorBinding: errorBinding)
        }

        private func observeItem(player: AVPlayer, statusBinding: Binding<PlayerStatus>, errorBinding: Binding<String?>) {
            statusObservation?.invalidate()
            errorObservation?.invalidate()
            guard let item = player.currentItem else { return }

            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay:
                        statusBinding.wrappedValue = .playing
                        errorBinding.wrappedValue = nil
                    case .failed:
                        statusBinding.wrappedValue = .error
                        errorBinding.wrappedValue = item.error?.localizedDescription ?? "Playback failed"
                    default:
                        statusBinding.wrappedValue = .buffering
                    }
                }
            }

            errorObservation = player.observe(\.currentItem?.error, options: [.new]) { _, change in
                if let err = change.newValue as? Error {
                    DispatchQueue.main.async {
                        statusBinding.wrappedValue = .error
                        errorBinding.wrappedValue = err.localizedDescription
                    }
                }
            }

            // Trigger once for current state
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    statusBinding.wrappedValue = .playing
                case .failed:
                    statusBinding.wrappedValue = .error
                    errorBinding.wrappedValue = item.error?.localizedDescription ?? "Playback failed"
                default:
                    statusBinding.wrappedValue = .buffering
                }
            }
        }

        deinit {
            statusObservation?.invalidate()
            rateObservation?.invalidate()
            errorObservation?.invalidate()
            itemObservation?.invalidate()
        }
    }
}

final class AVPlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspect }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

#endif
