//
//  FieldMappingView.swift
//  flashcard-widget
//
//  Prompts the user to map a newly-encountered note type's fields to
//  display roles (primary/secondary). Dismissing without finishing leaves
//  the note type unmapped -- import already happened and is never blocked
//  or rolled back by an incomplete mapping (apkg-import spec).
//

import SwiftUI
import SwiftData

struct FieldMappingView: View {
    let noteType: NoteType
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [PersistentIdentifier: FieldRole?] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(noteType.sortedFields) { field in
                        Picker(field.name, selection: binding(for: field)) {
                            Text("Unused").tag(FieldRole?.none)
                            Text("Primary").tag(FieldRole?.some(.primary))
                            Text("Secondary").tag(FieldRole?.some(.secondary))
                        }
                    }
                } header: {
                    Text("Map \"\(noteType.name)\" fields")
                } footer: {
                    Text("Primary is shown prominently; secondary fills in supporting detail. Unused fields are still stored.")
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
            .onAppear(perform: preloadDefaults)
        }
    }

    private func preloadDefaults() {
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
