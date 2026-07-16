import SwiftUI
import SwiftData
import StoreKit

/// Shown when the trial ends with more than three active stars. Two honest
/// paths, no dark patterns: unlock everything forever, or choose three stars
/// to keep lit. The rest *rest* — hidden, never deleted — and wake the
/// moment Kin is unlocked. This screen says so, plainly.
struct TrialEndedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics

    @Query(filter: #Predicate<Person> { $0.stateRaw != "released" && !$0.isDormant },
           sort: \Person.createdAt)
    private var people: [Person]

    let store = Store.shared
    @State private var keptIDs: Set<UUID> = []
    @State private var purchasing = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Text("Your seven nights are over.")
                    .font(KinType.heroLine).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Unlock Kin once and keep every star, forever. Or keep a free sky of three — the others will rest, not disappear. Every moment stays. Unlock anytime and they all return.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)

            Button {
                purchasing = true
                Task {
                    if await store.purchase() {
                        analytics.track(.purchase)
                        // RootView's gate clears itself; restoration is wired
                        // to isUnlocked there.
                    }
                    purchasing = false
                }
            } label: {
                Text(purchasing ? "One moment…"
                                : "Unlock Kin — \(store.lifetimeProduct?.displayPrice ?? "$4.99"), once")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom),
                        in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
            }
            .disabled(purchasing || store.lifetimeProduct == nil)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Button("Restore purchase") { Task { await store.restore() } }
                .font(.footnote).foregroundStyle(.white.opacity(0.45))
                .padding(.top, 10)

            HStack {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
                Text("or keep three lit")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
                    .fixedSize()
                Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(people) { person in starRow(person) }
                }
                .padding(.horizontal, 20)
            }

            Button(action: keepSelection) {
                Text(keptIDs.count == Store.freeStarLimit
                     ? "Keep these three lit"
                     : "Choose \(Store.freeStarLimit - keptIDs.count) more to keep")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(keptIDs.count == Store.freeStarLimit ? 0.7 : 0.25))
            .disabled(keptIDs.count != Store.freeStarLimit)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(Color(red: 0.02, green: 0.02, blue: 0.08).ignoresSafeArea())
        .onAppear {
            let days = Calendar.current.dateComponents([.day], from: store.firstLaunch, to: .now).day ?? 0
            analytics.track(.paywallViewed(daySinceInstall: days))
        }
    }

    private func starRow(_ person: Person) -> some View {
        let kept = keptIDs.contains(person.id)
        return HStack(spacing: 14) {
            Image(uiImage: SkyScene.starImage(
                temperature: SkyLayout.temperature(colorSeed: person.colorSeed)))
                .resizable().frame(width: 34, height: 34)
                .opacity(kept ? 1 : 0.45)
            Text(person.name)
                .font(KinType.whisper)
                .foregroundStyle(.white.opacity(kept ? 1 : 0.6))
            Spacer()
            Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(.white.opacity(kept ? 0.9 : 0.25))
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(kept ? .white.opacity(0.07) : .clear,
                    in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { toggle(person) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(kept ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(kept ? "Tap to let this star rest instead."
                                : "Tap to keep this star lit.")
    }

    private func toggle(_ person: Person) {
        if keptIDs.contains(person.id) {
            keptIDs.remove(person.id)
        } else if keptIDs.count < Store.freeStarLimit {
            keptIDs.insert(person.id)
            Haptics.shared.ignition(luminosity: 0.6)
        } else {
            // Already three: a soft no. Deselect something first.
            Haptics.shared.ignition(luminosity: 0.2)
        }
    }

    /// The chosen three stay; everyone else rests. Nothing is deleted —
    /// the gate in RootView clears on its own once ≤3 stars remain active.
    private func keepSelection() {
        guard keptIDs.count == Store.freeStarLimit else { return }
        let resting = people.filter { !keptIDs.contains($0.id) }
        for person in resting { person.isDormant = true }
        try? context.save()
        analytics.track(.starsRested(count: resting.count))
        publishSky(context: context) // widgets update immediately
        syncSiriVocabulary()         // Siri forgets resting names for now
        Haptics.shared.ignition(luminosity: 0.9)
    }
}
