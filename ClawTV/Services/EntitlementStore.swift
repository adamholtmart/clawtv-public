import Foundation
import StoreKit

@MainActor
final class EntitlementStore: ObservableObject {
    /// Product identifier for the one-time unlock IAP. Must match the
    /// .storekit configuration and App Store Connect listing.
    static let productID = "com.clawtv.player.unlock"

    /// Length of the free trial. Starts on first launch.
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var trialStart: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    private let trialStartKey = "clawtv.trialStart.v1"
    private var transactionListener: Task<Void, Never>?

    init() {
        if let saved = UserDefaults.standard.object(forKey: trialStartKey) as? Date {
            self.trialStart = saved
        } else {
            let now = Date()
            UserDefaults.standard.set(now, forKey: trialStartKey)
            self.trialStart = now
        }
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { transactionListener?.cancel() }

    /// True if the user is allowed in: either purchased, or still inside the 7-day window.
    var hasAccess: Bool { isPurchased || isInTrial }

    var isInTrial: Bool { trialRemaining > 0 && !isPurchased }

    /// Seconds remaining in the trial (clamped at 0).
    var trialRemaining: TimeInterval {
        guard let start = trialStart else { return Self.trialDuration }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, Self.trialDuration - elapsed)
    }

    var trialDaysRemaining: Int {
        Int(ceil(trialRemaining / (24 * 60 * 60)))
    }

    /// Pull the latest product and entitlement from StoreKit.
    func refresh() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            lastError = "Couldn't load store: \(error.localizedDescription)"
        }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.productID, tx.revocationDate == nil {
                purchased = true
            }
        }
        self.isPurchased = purchased
    }

    /// Kick off purchase flow. Updates `isPurchased` on success.
    func purchase() async {
        guard let product else {
            lastError = "Store unavailable. Please try again."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    isPurchased = true
                    lastError = nil
                } else {
                    lastError = "Purchase couldn't be verified."
                }
            case .userCancelled:
                lastError = nil
            case .pending:
                lastError = "Purchase pending approval."
            @unknown default:
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restore previously-purchased entitlements.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isPurchased {
                lastError = "No previous purchase found on this Apple ID."
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        if case .verified(let tx) = update, tx.productID == Self.productID {
            await tx.finish()
            await refreshEntitlement()
        }
    }
}
