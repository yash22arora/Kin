import SwiftUI
import SwiftData

/// Add a new star, or edit an existing one. The only place the free-tier
/// gate exists: a 4th star without full access shows the paywall.
struct StarFormSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @Query(filter: #Predicate<Person> { $0.stateRaw != "released" })
    private var people: [Person]

    /// nil = adding a new star
    let editing: Person?
    /// Where the star should ignite (unit coords), e.g. from a long-press
    /// on the sky. nil = seeded position.
    var birthPosition: (x: Double, y: Double)? = nil

    @State private var name = ""
    @State private var orbit: OrbitCadence = .weekly
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Their name", text: $name)
                }
                Section("How often do your paths cross?") {
                    ForEach(OrbitCadence.allCases, id: \.self) { cadence in
                        HStack {
                            Text(cadence.label)
                            Spacer()
                            if orbit == cadence {
                                Image(systemName: "checkmark").foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { orbit = cadence }
                        .accessibilityAddTraits(orbit == cadence ? .isSelected : [])
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.03, green: 0.03, blue: 0.10))
            .navigationTitle(editing == nil ? "A new star" : "Edit star")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .onAppear {
                if let person = editing {
                    name = person.name
                    orbit = person.orbit
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        defer { syncSiriVocabulary() } // names changed → Siri re-learns
        if let person = editing {
            person.name = trimmed
            person.orbit = orbit
            dismiss()
            return
        }
        guard Store.shared.canAddStar(currentCount: people.count) else {
            showPaywall = true
            return
        }
        let person = Person(name: trimmed, orbit: orbit)
        if let birthPosition {
            person.positionX = birthPosition.x
            person.positionY = birthPosition.y
        }
        context.insert(person)
        analytics.track(.starCreated(countBucket: people.count < 3 ? "1-3" : people.count < 7 ? "4-7" : "8+"))
        Haptics.shared.ignition(luminosity: 0.8)
        dismiss()
    }
}
