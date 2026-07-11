import SwiftUI
import SwiftData

/// One person, zoomed. Glow, light history, reach out. Never a number.
struct StarDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    let person: Person
    let onLogMoment: () -> Void

    @State private var showEdit = false
    @State private var showReleaseDialog = false
    @State private var editingMoment: Moment?

    private var sortedMoments: [Moment] {
        (person.moments ?? []).sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    starHeader
                    actions
                    yearAgoCard
                    lightHistory
                }
                .padding()
            }
            .background(.clear)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit star") { showEdit = true }
                        if person.state != .remembered {
                            Button("Remember forever") {
                                person.state = .remembered
                                analytics.track(.starRemembered)
                            }
                        }
                        Button("Release…", role: .destructive) { showReleaseDialog = true }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .sheet(isPresented: $showEdit) { StarFormSheet(editing: person) }
            .sheet(item: $editingMoment) { moment in
                // Presented identically to the log sheet in SkyView —
                // one component, one presentation. Keep these in sync.
                LogMomentSheet(editing: moment, preselectedPersonID: nil) { _ in }
                    .presentationDetents([.large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Release \(person.name)?",
                isPresented: $showReleaseDialog,
                titleVisibility: .visible
            ) {
                Button("Let their star drift away", role: .destructive, action: release)
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("Their star will leave your sky. Moments shared only with them will be deleted. This can't be undone.")
            }
        }
    }

    /// The release ritual. Deliberate, gentle, final.
    private func release() {
        for moment in person.moments ?? [] {
            let others = (moment.people ?? []).filter { $0.id != person.id }
            if others.isEmpty {
                if let photoID = moment.photoID { PhotoStore.delete(id: photoID) }
                context.delete(moment)
            } else {
                moment.people = others // shared moments stay with the others
            }
        }
        context.delete(person)
        analytics.track(.starReleased)
        syncSiriVocabulary() // released stars leave Siri's vocabulary too
        dismiss()
    }

    private var starHeader: some View {
        VStack(spacing: 12) {
            // No rendered star here — the actual star, camera-zoomed,
            // hangs in the sky above this sheet. The sheet is just words.
            let lum = person.luminosity()
            Text(person.name)
                .font(KinType.title)
                .foregroundStyle(.white)
                .padding(.top, 8)
                .accessibilityLabel("\(person.name). \(lum > 0.7 ? "Bright" : lum > 0.45 ? "Glowing" : "Distant").")
            if person.state == .remembered {
                Text("Remembered").font(.footnote.smallCaps()).foregroundStyle(.white.opacity(0.5))
            } else if let last = sortedMoments.first {
                Text("Last moment \(last.timestamp.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss(); onLogMoment() }) {
                Label("Log a moment", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.white.opacity(0.15))

            // Kin never sends anything itself — this just opens the share sheet.
            ShareLink(item: "Thinking of you ✨") {
                Label("Reach out", systemImage: "paperplane")
            }
            .buttonStyle(.bordered).tint(.white.opacity(0.3))
        }
    }

    /// "A year ago tonight" — resurfacing, the quiet gift.
    @ViewBuilder
    private var yearAgoCard: some View {
        let calendar = Calendar.current
        if let yearAgo = calendar.date(byAdding: .year, value: -1, to: .now),
           let match = sortedMoments.first(where: { calendar.isDate($0.timestamp, inSameDayAs: yearAgo) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A year ago tonight").font(.caption.smallCaps()).foregroundStyle(.white.opacity(0.5))
                if !match.note.isEmpty {
                    Text(match.note).font(.callout).foregroundStyle(.white.opacity(0.9))
                }
                if let photoID = match.photoID, let image = PhotoStore.image(for: photoID) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var lightHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sortedMoments.isEmpty {
                Text("No moments yet. Even one light is enough to find your way.")
                    .font(.callout).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
            ForEach(sortedMoments) { moment in
                HStack(alignment: .top, spacing: 12) {
                    // Pulse: brighter = richer moment
                    Circle()
                        .fill(.white.opacity(moment.note.isEmpty ? 0.3 : 0.8))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(moment.timestamp.formatted(.dateTime.month().day().year()))
                            .font(.caption).foregroundStyle(.white.opacity(0.4))
                        if !moment.note.isEmpty {
                            Text(moment.note).font(.body).foregroundStyle(.white.opacity(0.85))
                        }
                        if let photoID = moment.photoID, let image = PhotoStore.image(for: photoID) {
                            Image(uiImage: image)
                                .resizable().scaledToFill()
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        if let feeling = moment.feeling {
                            Image(systemName: feeling.symbolName)
                                .font(.caption).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { editingMoment = moment }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edit this moment")
            }
        }
    }
}
