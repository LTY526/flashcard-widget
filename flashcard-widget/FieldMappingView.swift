//
//  FieldMappingView.swift
//  flashcard-widget
//
//  Prompts the user to map a note type's fields to display roles
//  (primary/secondary/tertiary). Reused both for a newly-encountered note type and
//  for editing an already-mapped one at any time -- mapping isn't a
//  one-time onboarding step, the user can revisit it whenever they want to
//  change what's shown. Dismissing without finishing an unmapped note type
//  leaves it unmapped; import is never blocked or rolled back by an
//  incomplete mapping (apkg-import spec). A live preview of a sample card,
//  driven by the in-progress (unsaved) selections rather than the note
//  type's stored roles, helps the user judge fields before committing.
//
//  A note type's mapping is shared globally (keyed by `ankiNoteTypeID`, per
//  ADR 0001 decision 4): editing it from one deck affects every other deck
//  that reuses the same note type, including decks not currently open.
//

import SwiftUI
import SwiftData

struct FieldMappingView: View {
    let noteType: NoteType
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [PersistentIdentifier: FieldRole?] = [:]
    @State private var sampleNote: Note?

    private var candidateNotes: [Note] {
        noteType.notes.filter { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    previewContent
                    Button {
                        pickRandomSample()
                    } label: {
                        Label("Try another card", systemImage: "shuffle")
                    }
                    .disabled(candidateNotes.count <= 1)
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Shows how a sample card would look with the mapping below.")
                }

                Section {
                    ForEach(noteType.sortedFields) { field in
                        Picker(field.name, selection: binding(for: field)) {
                            Text("Unused").tag(FieldRole?.none)
                            Text("Primary").tag(FieldRole?.some(.primary))
                            Text("Secondary").tag(FieldRole?.some(.secondary))
                            Text("Tertiary").tag(FieldRole?.some(.tertiary))
                        }
                    }
                } header: {
                    Text("Map \"\(noteType.name)\" fields")
                } footer: {
                    Text("Primary is shown prominently; secondary fills in supporting detail; tertiary adds in-app detail. Unused fields are still stored. This mapping applies to every deck that shares this note type.")
                }
            }
            .navigationTitle("Field Mapping")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        dismiss()
                        onFinished()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applySelections()
                        dismiss()
                        onFinished()
                    }
                }
            }
            .onAppear {
                preloadSelections()
                pickRandomSample()
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if sampleNote != nil {
            CardWidgetView(
                primary: previewText(for: .primary),
                secondary: previewText(for: .secondary),
                tertiary: previewText(for: .tertiary)
            )
        } else {
            Text("No sample cards available yet")
                .foregroundStyle(.secondary)
        }
    }

    private func previewText(for role: FieldRole) -> String? {
        guard let sampleNote else { return nil }
        let values: [String] = noteType.sortedFields.compactMap { field in
            guard (selections[field.persistentModelID] ?? nil) == role else { return nil }
            guard field.ordinal >= 0, field.ordinal < sampleNote.fieldValues.count else { return nil }
            return Note.plainText(from: sampleNote.fieldValues[field.ordinal])
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " / ")
    }

    private func pickRandomSample() {
        sampleNote = candidateNotes.randomElement()
    }

    /// Starts from whatever's already saved on this note type (so editing
    /// picks up where the user left off); only falls back to a heuristic
    /// guess when nothing has ever been assigned yet.
    private func preloadSelections() {
        let hasExistingMapping = noteType.fields.contains { $0.role != nil }
        if hasExistingMapping {
            for field in noteType.fields {
                selections[field.persistentModelID] = field.role
            }
            return
        }
        let defaults = FieldMappingService.heuristicDefaultMapping(for: noteType)
        for field in noteType.fields {
            if defaults.primary.contains(field.name) {
                selections[field.persistentModelID] = .primary
            } else if defaults.secondary.contains(field.name) {
                selections[field.persistentModelID] = .secondary
            } else {
                selections[field.persistentModelID] = FieldRole?.none
            }
        }
    }

    private func applySelections() {
        for field in noteType.fields {
            field.role = selections[field.persistentModelID] ?? nil
        }
    }

    private func binding(for field: NoteTypeField) -> Binding<FieldRole?> {
        Binding(
            get: { selections[field.persistentModelID] ?? nil },
            set: { selections[field.persistentModelID] = $0 }
        )
    }
}
