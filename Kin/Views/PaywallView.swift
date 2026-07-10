import SwiftUI
import SwiftData
import StoreKit

/// The user's own sky is the pitch. Transparent, no dark patterns.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @Query(filter: #Predicate<Person> { $0.stateRaw != "released" })
    private var people: [Person]
    @Query private var moments: [Moment]

    let store = Store.shared
    @State private var purchasing = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.9))

            Text("Your sky has \(people.count) stars\nand \(moments.count) moments.")
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("Keep tending it. \(priceLabel), once, forever.\nNo subscription. No account.\nYour sky never leaves your device.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Button {
                purchasing = true
                Task {
                    if await store.purchase() {
                        analytics.track(.purchase)
                        dismiss()
                    }
                    purchasing = false
                }
            } label: {
                Text(purchasing ? "One moment…" : "Unlock Kin")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
            .disabled(purchasing || store.lifetimeProduct == nil)

            Button("Restore purchase") {
                Task { await store.restore(); if store.isUnlocked { dismiss() } }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.5))

            Button("Keep the free sky (3 stars)") { dismiss() }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(32)
        .background(Color(red: 0.02, green: 0.02, blue: 0.08))
        .onAppear {
            let days = Calendar.current.dateComponents([.day], from: store.firstLaunch, to: .now).day ?? 0
            analytics.track(.paywallViewed(daySinceInstall: days))
        }
    }

    private var priceLabel: String {
        store.lifetimeProduct?.displayPrice ?? "$4.99"
    }
}
