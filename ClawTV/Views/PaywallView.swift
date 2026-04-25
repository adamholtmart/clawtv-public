import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var entitlement: EntitlementStore
    @FocusState private var focused: Field?

    private enum Field: Hashable { case unlock, restore }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.10),
                         Color(red: 0.10, green: 0.04, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 56) {
                VStack(spacing: 20) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.tint)
                    Text("ClawTV")
                        .font(.system(size: 90, weight: .heavy, design: .rounded))
                    Text("Your free trial has ended.")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    bullet("Beautiful, native tvOS player for any M3U playlist")
                    bullet("Built-in EPG / program guide via your XMLTV source")
                    bullet("Multi-View — watch up to four channels at once")
                    bullet("Favorites, history, and instant search")
                    bullet("Buy once. Own forever. No subscriptions.")
                }
                .frame(maxWidth: 880, alignment: .leading)

                VStack(spacing: 18) {
                    Button {
                        Task { await entitlement.purchase() }
                    } label: {
                        HStack(spacing: 12) {
                            if entitlement.isPurchasing {
                                ProgressView()
                            } else {
                                Image(systemName: "lock.open.fill")
                            }
                            Text(unlockLabel)
                                .font(.title3.weight(.semibold))
                        }
                        .frame(minWidth: 520)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .focused($focused, equals: .unlock)
                    .disabled(entitlement.isPurchasing)

                    Button {
                        Task { await entitlement.restore() }
                    } label: {
                        HStack(spacing: 10) {
                            if entitlement.isRestoring {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            Text("Restore Purchase")
                        }
                        .frame(minWidth: 520)
                    }
                    .buttonStyle(.bordered)
                    .focused($focused, equals: .restore)
                    .disabled(entitlement.isRestoring)

                    if let err = entitlement.lastError {
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 80)
        }
        .task {
            await entitlement.refresh()
            focused = .unlock
        }
    }

    private var unlockLabel: String {
        if let display = entitlement.product?.displayPrice {
            return "Unlock ClawTV — \(display)"
        }
        return "Unlock ClawTV"
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            Text(text)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}
