import StoreKit
import SwiftUI

/// StoreKit 2 wrapper. One product, one price, forever — the honest deal.
/// Free tier: 3 stars, unlimited moments. 7-day trial of everything.
@Observable
final class Store {
    static let shared = Store()

    static let lifetimeProductID = "com.servatom.kin.lifetime"
    static let freeStarLimit = 3
    static let trialDays = 7

    private(set) var lifetimeProduct: Product?
    /// Seeded from the last verified check so cold launches don't flash the
    /// trial gate while StoreKit wakes up. The async entitlement check runs
    /// at every launch/foreground and corrects this if it's ever wrong.
    private(set) var isUnlocked = UserDefaults.standard.bool(forKey: "isUnlocked")
    private var transactionListener: Task<Void, Never>?

    @MainActor
    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        UserDefaults.standard.set(value, forKey: "isUnlocked")
    }

    // MARK: Trial
    // Anchored to AppTransaction.originalPurchaseDate (survives reinstalls);
    // falls back to a stored first-launch date until StoreKit responds.

    private(set) var firstLaunch: Date = {
        let defaults = UserDefaults.standard
        if let date = defaults.object(forKey: "firstLaunch") as? Date { return date }
        let now = Date()
        defaults.set(now, forKey: "firstLaunch")
        return now
    }()

    @MainActor
    private func anchorTrialToAppTransaction() async {
        // The local StoreKit test environment reports originalPurchaseDate
        // as the day the test store first saw this app — days in the past —
        // which silently expires every fresh debug install. The anchor only
        // means something against the real App Store; debug builds skip it.
        #if !DEBUG
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else { return }
        let original = transaction.originalPurchaseDate
        // Use the earlier of the two — never extend a trial on reinstall.
        if original < firstLaunch {
            firstLaunch = original
            UserDefaults.standard.set(original, forKey: "firstLaunch")
        }
        #endif
    }

    #if DEBUG
    /// Flip to true to mimic an expired trial (drives the TrialEndedView
    /// flow when more than 3 stars exist). Debug builds only.
    static let debugForceTrialEnded = false
    #endif

    var trialEndsAt: Date { firstLaunch.addingTimeInterval(Double(Self.trialDays) * 86_400) }

    var isTrialActive: Bool {
        #if DEBUG
        if Self.debugForceTrialEnded { return false }
        #endif
        return Date() < trialEndsAt
    }
    var hasFullAccess: Bool { isUnlocked || isTrialActive }

    /// The single gate in the app: adding a star beyond the free tier.
    func canAddStar(currentCount: Int) -> Bool {
        hasFullAccess || currentCount < Self.freeStarLimit
    }

    // MARK: StoreKit

    func start() {
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
            await anchorTrialToAppTransaction()
        }
    }

    @MainActor
    func loadProducts() async {
        lifetimeProduct = try? await Product.products(for: [Self.lifetimeProductID]).first
    }

    @MainActor
    func refreshEntitlements() async {
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.lifetimeProductID {
                unlocked = true
                break
            }
        }
        setUnlocked(unlocked)
    }

    @MainActor
    @discardableResult
    func purchase() async -> Bool {
        guard let product = lifetimeProduct else { return false }
        guard let result = try? await product.purchase() else { return false }
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
            setUnlocked(true)
            return true
        }
        return false
    }

    @MainActor
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
