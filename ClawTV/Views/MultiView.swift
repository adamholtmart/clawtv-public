import SwiftUI

struct MultiView: View {
    let onExit: () -> Void

    @EnvironmentObject var store: PlaylistStore
    @State private var slots: [Channel?] = [nil, nil, nil, nil]
    @State private var audioSlot: Int = 0
    @State private var pickerSlot: Int? = nil
    @State private var focusedSlot: Int? = nil

    private var activeCount: Int { slots.compactMap { $0 }.count }
    private var pickerActive: Bool { pickerSlot != nil }

    private func openPicker(slot: Int) {
        // Defer the cover present by a beat so the contextMenu can fully
        // dismiss before a second fullScreenCover starts inflating. Without
        // this the menu dismiss animation overlaps the picker's heavy
        // LazyVGrid materialization, which on tvOS either locks the main
        // thread or bounces us out of Multi-View entirely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pickerSlot = slot
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if activeCount == 0 {
                    EmptyState { openPicker(slot: 0) }
                } else {
                    stableGrid(in: CGSize(width: geo.size.width - 24, height: geo.size.height - 24))
                        .padding(12)
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { pickerSlot.map { PickerTarget(slot: $0) } },
            set: { pickerSlot = $0?.slot }
        )) { target in
            MultiViewAddChannelView(
                slotIndex: target.slot,
                currentChannel: slots[target.slot],
                onPick: { channel in
                    slots[target.slot] = channel
                    if activeCount == 1 { audioSlot = target.slot }
                    pickerSlot = nil
                },
                onCancel: { pickerSlot = nil }
            )
        }
        .onExitCommand { onExit() }
        .onAppear {
            if let restored = store.consumeMultiViewSlots() {
                slots = restored.slots
                if restored.audioSlot >= 0 && restored.audioSlot < slots.count && slots[restored.audioSlot] != nil {
                    audioSlot = restored.audioSlot
                } else if let firstActive = slots.firstIndex(where: { $0 != nil }) {
                    audioSlot = firstActive
                }
                _ = store.consumeMultiViewSeed()
                return
            }
            if let seed = store.consumeMultiViewSeed() {
                if let empty = slots.firstIndex(where: { $0 == nil }) {
                    slots[empty] = seed
                    audioSlot = empty
                    if let nextEmpty = slots.firstIndex(where: { $0 == nil }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            pickerSlot = nextEmpty
                        }
                    }
                }
            }
        }
    }

    // Renders all active tiles inside a single ZStack with stable identities
    // (keyed by slot index), positioning them via computed frames. This keeps
    // each MultiTile's VLCPlayerView alive across activeCount transitions — so
    // going 2→3 adds a single new decoder instead of tearing down two tiles
    // and recreating three simultaneously (which on ATV causes a memory/CPU
    // spike heavy enough to crash the app).
    @ViewBuilder
    private func stableGrid(in size: CGSize) -> some View {
        let active = activeSlotIndices()
        let focusedRank: Int? = focusedSlot.flatMap { active.firstIndex(of: $0) }
        ZStack(alignment: .topLeading) {
            ForEach(0..<slots.count, id: \.self) { idx in
                if slots[idx] != nil {
                    let rank = active.firstIndex(of: idx) ?? 0
                    let rect = frame(for: rank, count: active.count, focusedRank: focusedRank, in: size)
                    tile(idx)
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                        .zIndex(focusedSlot == idx ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: active.count)
                        .animation(.easeInOut(duration: 0.3), value: focusedSlot)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func activeSlotIndices() -> [Int] {
        slots.enumerated().compactMap { $0.element == nil ? nil : $0.offset }
    }

    private func frame(for rank: Int, count: Int, focusedRank: Int?, in size: CGSize) -> CGRect {
        let gap: CGFloat = 12
        let w = size.width
        let h = size.height

        if let focusedRank, count >= 2 {
            // Main tile on left ~72%, secondaries stacked on right ~28%.
            let mainW = (w - gap) * 0.72
            let sideW = w - mainW - gap

            if rank == focusedRank {
                return CGRect(x: 0, y: 0, width: mainW, height: h)
            }

            let others = count - 1
            let sideIndex: Int = {
                var visited = 0
                for r in 0..<count where r != focusedRank {
                    if r == rank { return visited }
                    visited += 1
                }
                return 0
            }()
            let eachH = (h - gap * CGFloat(max(others - 1, 0))) / CGFloat(others)
            let y = CGFloat(sideIndex) * (eachH + gap)
            return CGRect(x: mainW + gap, y: y, width: sideW, height: eachH)
        }

        switch count {
        case 1:
            return CGRect(x: 0, y: 0, width: w, height: h)
        case 2:
            let cw = (w - gap) / 2
            return CGRect(x: CGFloat(rank) * (cw + gap), y: 0, width: cw, height: h)
        case 3:
            let cw = (w - gap) / 2
            let ch = (h - gap) / 2
            if rank < 2 {
                return CGRect(x: CGFloat(rank) * (cw + gap), y: 0, width: cw, height: ch)
            } else {
                return CGRect(x: 0, y: ch + gap, width: w, height: ch)
            }
        default:
            let cw = (w - gap) / 2
            let ch = (h - gap) / 2
            let row = rank / 2
            let col = rank % 2
            return CGRect(x: CGFloat(col) * (cw + gap), y: CGFloat(row) * (ch + gap), width: cw, height: ch)
        }
    }

    @ViewBuilder
    private func tile(_ index: Int) -> some View {
        if let channel = slots[index] {
            MultiTile(
                channel: channel,
                muted: audioSlot != index,
                isAudioActive: audioSlot == index,
                paused: pickerActive,
                isFocused: focusedSlot == index,
                someoneElseFocused: focusedSlot != nil && focusedSlot != index,
                canFocus: activeCount >= 2,
                onMakeAudio: { audioSlot = index },
                onReplace: { openPicker(slot: index) },
                onRemove: {
                    slots[index] = nil
                    if audioSlot == index {
                        audioSlot = slots.firstIndex(where: { $0 != nil }) ?? 0
                    }
                    if focusedSlot == index { focusedSlot = nil }
                },
                onAdd: activeCount < 4 ? {
                    if let empty = slots.firstIndex(where: { $0 == nil }) {
                        openPicker(slot: empty)
                    }
                } : nil,
                onPromote: {
                    store.promoteFromMultiView(channel: channel, slots: slots, audioSlot: audioSlot)
                },
                onToggleFocus: {
                    focusedSlot = (focusedSlot == index) ? nil : index
                    audioSlot = index
                },
                onExitMulti: onExit
            )
        }
    }
}

private struct PickerTarget: Identifiable {
    let slot: Int
    var id: Int { slot }
}

private struct EmptyState: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.4))
            Text("Multi-View")
                .font(.title).bold()
            Text("Watch up to 4 channels at once.")
                .foregroundStyle(.secondary)
            Button(action: onAdd) {
                Label("Add Channel", systemImage: "plus")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }
}

private struct MultiTile: View {
    let channel: Channel
    let muted: Bool
    let isAudioActive: Bool
    let paused: Bool
    let isFocused: Bool
    let someoneElseFocused: Bool
    let canFocus: Bool
    let onMakeAudio: () -> Void
    let onReplace: () -> Void
    let onRemove: () -> Void
    let onAdd: (() -> Void)?
    let onPromote: () -> Void
    let onToggleFocus: () -> Void
    let onExitMulti: () -> Void

    @State private var status: PlayerStatus = .loading
    @State private var errorText: String?
    @State private var infoVisible: Bool = true
    @State private var hideTask: Task<Void, Never>? = nil
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black
            VLCPlayerView(url: channel.streamURL, status: $status, errorText: $errorText, muted: muted, paused: paused)

            VStack {
                if status == .error {
                    Text(errorText ?? "Stream failed")
                        .font(.caption)
                        .padding(10)
                        .background(.black.opacity(0.7), in: .rect(cornerRadius: 8))
                }
                Spacer()
                HStack {
                    Text(channel.name)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: .capsule)
                    Spacer()
                    if isAudioActive {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .padding(8)
                            .background(.black.opacity(0.6), in: .circle)
                    } else {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.black.opacity(0.6), in: .circle)
                    }
                }
                .opacity(infoVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: infoVisible)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(focused ? Color.white : (isAudioActive ? Color.accentColor : Color.white.opacity(0.1)),
                        lineWidth: focused ? 4 : (isAudioActive ? 3 : 1))
        )
        .scaleEffect(focused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .focusable(true)
        .focused($focused)
        .onTapGesture { onMakeAudio() }
        .onChange(of: focused) { _, newValue in
            if newValue {
                showInfoThenHide()
            }
        }
        .onChange(of: isAudioActive) { _, _ in
            showInfoThenHide()
        }
        .onChange(of: status) { _, newValue in
            if newValue == .playing {
                showInfoThenHide()
            } else if newValue == .error {
                infoVisible = true
                hideTask?.cancel()
            }
        }
        .onAppear { showInfoThenHide() }
        .onDisappear { hideTask?.cancel() }
        .contextMenu {
            Button {
                onPromote()
            } label: {
                Label("Watch Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                onMakeAudio()
            } label: {
                Label("Unmute", systemImage: "speaker.wave.2.fill")
            }
            .disabled(isAudioActive)

            if canFocus {
                Button {
                    onToggleFocus()
                } label: {
                    if isFocused {
                        Label("Exit Focus", systemImage: "rectangle.split.2x2")
                    } else if someoneElseFocused {
                        Label("Make This the Focus", systemImage: "rectangle.inset.filled")
                    } else {
                        Label("Focus Channel", systemImage: "rectangle.inset.filled")
                    }
                }
            }

            Button {
                onReplace()
            } label: {
                Label("Replace Channel", systemImage: "arrow.triangle.2.circlepath")
            }

            if let onAdd {
                Button {
                    onAdd()
                } label: {
                    Label("Add Channel", systemImage: "plus")
                }
            }

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }

            Divider()

            Button {
                onExitMulti()
            } label: {
                Label("Exit Multi-View", systemImage: "xmark.circle")
            }
        }
    }

    private func showInfoThenHide() {
        hideTask?.cancel()
        infoVisible = true
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                if status != .error {
                    infoVisible = false
                }
            }
        }
    }
}

