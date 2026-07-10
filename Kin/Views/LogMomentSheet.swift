import SwiftUI
import SwiftData
import PhotosUI
import AppIntents

/// One tap + one line. Everything optional except who.
/// Doubles as the editor: pass `editing` to modify or delete a moment.
/// Custom layout (no Form) — the sheet is a quiet surface over the sky.
struct LogMomentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analytics) private var analytics
    @Query private var people: [Person]
    @FocusState private var noteFocused: Bool

    /// nil = logging a new moment.
    var editing: Moment? = nil
    let preselectedPersonID: UUID?
    /// Called on save with involved person IDs (drives the shooting star).
    /// Edits don't shoot stars — the moment already happened.
    let onSaved: ([UUID]) -> Void

    @State private var selectedIDs: Set<UUID> = []
    @State private var note = ""
    @State private var feeling: Feeling?
    @State private var date = Date()
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?          // newly picked photo
    @State private var existingPhotoID: String?  // photo already on the moment
    @State private var showDeleteDialog = false

    private static let placeholders = [
        "What made you smile?",
        "A small thing you'll want to remember…",
        "What did you talk about?",
        "Where were you?",
    ]
    private let placeholder = Self.placeholders.randomElement()!

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 20) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    peopleChips
                    noteField
                    feelingsRow
                    photoAndDate
                    photoPreview
                    if isEditing { deleteButton }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 18)
        .confirmationDialog(
            "Let this moment go?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Delete moment", role: .destructive, action: deleteMoment)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The stars it warmed will dim a little. This can't be undone.")
        }
        .onAppear(perform: prefill)
        .task(id: pickerItem) {
            guard let item = pickerItem else { return }
            photoData = try? await item.loadTransferable(type: Data.self)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Button("Not now") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(isEditing ? "This moment" : "A moment")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button("Save", action: save)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedIDs.isEmpty ? .white.opacity(0.25) : .white)
                .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
    }

    private var peopleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(people.filter { $0.state == .active }) { person in
                    personChip(person)
                }
            }
        }
    }

    private func personChip(_ person: Person) -> some View {
        let selected = selectedIDs.contains(person.id)
        return Text(person.name)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? .white.opacity(0.2) : .white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.5 : 0.12)))
            .onTapGesture {
                if selected { selectedIDs.remove(person.id) } else { selectedIDs.insert(person.id) }
                Haptics.shared.ignition(luminosity: person.luminosity())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var noteField: some View {
        TextField(placeholder, text: $note, axis: .vertical)
            .lineLimit(4, reservesSpace: true)
            .focused($noteFocused)
            .foregroundStyle(.white)
            .tint(.white.opacity(0.7))
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: note) { _, new in
                if new.count > 280 { note = String(new.prefix(280)) }
            }
    }

    private var feelingsRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Feeling.allCases, id: \.self) { f in
                    Image(systemName: f.symbolName)
                        .font(.body)
                        .foregroundStyle(feeling == f ? .white : .white.opacity(0.3))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                feeling = (feeling == f) ? nil : f
                            }
                        }
                        .accessibilityLabel(f.whisper)
                        .accessibilityAddTraits(feeling == f ? .isSelected : [])
                }
            }
            Text(feeling?.whisper ?? "How did it feel? Optional.")
                .font(.caption)
                .foregroundStyle(.white.opacity(feeling == nil ? 0.3 : 0.55))
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: 0.2), value: feeling)
        }
    }

    private var photoAndDate: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: hasPhoto ? "photo.fill" : "photo")
                    .foregroundStyle(.white.opacity(hasPhoto ? 0.9 : 0.35))
                    .frame(minWidth: 44, minHeight: 36)
            }
            .accessibilityLabel(hasPhoto ? "Photo added" : "Add a photo")
            Spacer()
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .fixedSize()
                .colorScheme(.dark)
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let image = previewImage {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(maxHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    Button {
                        photoData = nil
                        pickerItem = nil
                        existingPhotoID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(6)
                    .accessibilityLabel("Remove photo")
                }
        }
    }

    private var deleteButton: some View {
        Button("Let this moment go", role: .destructive) {
            showDeleteDialog = true
        }
        .font(.subheadline)
        .padding(.top, 4)
    }

    // MARK: State helpers

    private var hasPhoto: Bool { photoData != nil || existingPhotoID != nil }

    private var previewImage: UIImage? {
        if let photoData { return UIImage(data: photoData) }
        if let existingPhotoID { return PhotoStore.image(for: existingPhotoID) }
        return nil
    }

    private func prefill() {
        if let moment = editing {
            selectedIDs = Set((moment.people ?? []).map(\.id))
            note = moment.note
            feeling = moment.feeling
            date = moment.timestamp
            existingPhotoID = moment.photoID
        } else if let id = preselectedPersonID {
            selectedIDs.insert(id)
        }
    }

    // MARK: Save / delete

    private func save() {
        let involved = people.filter { selectedIDs.contains($0.id) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let backdated = !Calendar.current.isDateInToday(date)

        if let moment = editing {
            moment.timestamp = date
            moment.note = trimmed
            moment.people = involved
            moment.feeling = feeling
            moment.isBackdated = backdated
            if let photoData {
                if let old = moment.photoID { PhotoStore.delete(id: old) }
                moment.photoID = PhotoStore.save(photoData)
            } else if existingPhotoID == nil, let old = moment.photoID {
                PhotoStore.delete(id: old)
                moment.photoID = nil
            }
            analytics.track(.momentEdited)
            onSaved([])
            dismiss()
            return
        }

        let moment = Moment(
            timestamp: date, note: trimmed, people: involved,
            feeling: feeling, isBackdated: backdated
        )
        if let photoData, let photoID = PhotoStore.save(photoData) {
            moment.photoID = photoID
        }
        context.insert(moment)
        analytics.track(.momentLogged(
            source: preselectedPersonID == nil ? "sky" : "star",
            hasNote: !trimmed.isEmpty,
            hasPhoto: moment.photoID != nil,
            peopleCount: involved.count,
            backdated: backdated
        ))
        onSaved(involved.map(\.id))
        donate(for: involved)
        dismiss()
    }

    /// Teach Siri (and Apple Intelligence) the pattern: this user logs
    /// moments with these people. Powers suggestions on the lock screen,
    /// in Spotlight, and in the new Siri.
    private func donate(for involved: [Person]) {
        guard let first = involved.first else { return }
        let intent = LogMomentIntent()
        intent.person = PersonEntity(person: first)
        Task { try? await IntentDonationManager.shared.donate(intent: intent) }
    }

    private func deleteMoment() {
        guard let moment = editing else { return }
        if let photoID = moment.photoID { PhotoStore.delete(id: photoID) }
        context.delete(moment)
        analytics.track(.momentDeleted)
        onSaved([])
        dismiss()
    }
}
