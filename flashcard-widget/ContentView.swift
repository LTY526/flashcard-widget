//
//  ContentView.swift
//  flashcard-widget
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]

    @State private var isShowingFileImporter = false
    @State private var importErrorMessage: String?
    @State private var noteTypeNeedingMapping: NoteType?
    @State private var pendingNoteTypeIDsNeedingMapping: [PersistentIdentifier] = []

    private var apkgContentType: UTType {
        UTType(filenameExtension: "apkg", conformingTo: .zip) ?? .zip
    }

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    ContentUnavailableView(
                        "No decks yet",
                        systemImage: "rectangle.stack",
                        description: Text("Import an Anki .apkg file to get started.")
                    )
                } else {
                    List {
                        ForEach(decks) { deck in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(deck.name)
                                    Text("\(deck.activeCards.count) cards")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if deck.needsFieldMapping {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Needs field mapping")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Import .apkg", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [apkgContentType],
                allowsMultipleSelection: false
            ) { result in
                handleFileImportResult(result)
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )
            ) {
                Button("OK") { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .sheet(item: $noteTypeNeedingMapping) { noteType in
                FieldMappingView(noteType: noteType, onFinished: presentNextMappingPromptIfNeeded)
            }
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            importErrorMessage = ApkgImportError.notAnApkg.errorDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importResult = try ApkgImporter.importApkg(fileURL: url, modelContext: modelContext)
                pendingNoteTypeIDsNeedingMapping = importResult.noteTypesNeedingMapping
                presentNextMappingPromptIfNeeded()
            } catch let error as ApkgImportError {
                importErrorMessage = error.errorDescription
            } catch {
                importErrorMessage = ApkgImportError.damagedCollection.errorDescription
            }
        }
    }

    private func presentNextMappingPromptIfNeeded() {
        guard !pendingNoteTypeIDsNeedingMapping.isEmpty else {
            noteTypeNeedingMapping = nil
            return
        }
        let nextID = pendingNoteTypeIDsNeedingMapping.removeFirst()
        noteTypeNeedingMapping = modelContext.model(for: nextID) as? NoteType
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Deck.self, inMemory: true)
}
