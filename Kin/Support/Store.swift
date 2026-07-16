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
    private(set) var isUnlocked = false
    private var transactionListener: Task<Void, Never>?

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
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else { return }
        let original = transaction.originalPurchaseDate
        // Use the earlier of the two — never extend a trial on reinstall.
        if original < firstLaunch {
            firstLaunch = original
            UserDefaults.standard.set(original, forKey: "firstLaunch")
        }
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
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.lifetimeProductID {
                isUnlocked = true
                return
            }
        }
        isUnlocked = false
    }

    @MainActor
    @discardableResult
    func purchase() async -> Bool {
        guard let product = lifetimeProduct else { return false }
        guard let result = try? await product.purchase() else { return false }
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
            isUnlocked = true
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
