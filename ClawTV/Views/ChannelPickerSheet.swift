import SwiftUI

struct ChannelPickerSheet: View {
    @EnvironmentObject var resolver: ChannelResolver
    let epg: EPGChannel
    let candidates: [ScoredChannel]
    let onPick: (Channel, Bool) -> Void
    let onDismiss: () -> Void

    @State private var rememberPick: Bool = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                header

                if candidates.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(candidates) { scored in
                                candidateButton(scored)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.bottom, 40)
                    }
                }

                if !candidates.isEmpty {
                    controls
                }
            }
            .padding(.vertical, 24)
            .navigationTitle("Find a stream")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(epg.displayName)
                .font(.system(size: 34, weight: .bold))
            HStack(spacing: 10) {
                Text(epg.id)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if resolver.hasSavedPick(for: epg) {
                    Label("Saved pick exists", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            Text("Pick the stream that matches this channel. We'll remember it for next time.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.tv")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No likely streams found")
                .font(.headline)
            Text("Your playlist doesn't appear to carry this channel, or the name is too different to match automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80)
            Button("Close", action: onDismiss)
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private func candidateButton(_ scored: ScoredChannel) -> some View {
        Button {
            onPick(scored.channel, rememberPick)
        } label: {
            HStack(alignment: .center, spacing: 16) {
                if let logo = scored.channel.logoURL {
                    AsyncImage(url: logo) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        default: Image(systemName: "tv.fill").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .frame(width: 56, height: 56)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(scored.channel.name)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(1)
                    Text(scored.channel.groupTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(scored.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                scoreBadge(scored.score)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.card)
    }

    private func scoreBadge(_ score: Int) -> some View {
        let color: Color
        switch score {
        case 90...:  color = .green
        case 70...:  color = .yellow
        case 50...:  color = .orange
        default:     color = .gray
        }
        return Text("\(score)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.8), in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button {
                rememberPick.toggle()
            } label: {
                Label(rememberPick ? "Will remember my pick" : "Won't remember",
                      systemImage: rememberPick ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.bordered)
            .tint(rememberPick ? .accentColor : .gray)

            Spacer()

            if resolver.hasSavedPick(for: epg) {
                Button(role: .destructive) {
                    resolver.forget(epg: epg)
                } label: {
                    Label("Clear saved", systemImage: "xmark.bin")
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel", action: onDismiss)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 60)
    }
}
