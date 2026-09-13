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
    @State private var isImporting = false
    @State private var isRemoving = false
    @State private var importErrorMessage: String?
    @State private var noteTypeNeedingMapping: NoteType?
    @State private var pendingNoteTypeIDsNeedingMapping: [PersistentIdentifier] = []
    @State private var deckPendingRemoval: Deck?

    private var apkgContentType: UTType {
        UTType(importedAs: "net.ankiweb.apkg", conformingTo: .zip)
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
                                    Button {
                                        editMapping(for: deck)
                                    } label: {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Needs field mapping")
                                    .accessibilityHint("Tap to fix")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deckPendingRemoval = deck
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                Button {
                                    editMapping(for: deck)
                                } label: {
                                    Label("Edit Mapping", systemImage: "slider.horizontal.3")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem {
                    if isImporting || isRemoving {
                        ProgressView()
                    } else {
                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label("Import .apkg", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .disabled(isImporting || isRemoving)
            .overlay {
                if isImporting || isRemoving {
                    ZStack {
                        Color.black.opacity(0.05)
                        ProgressView(isImporting ? "Importing deck…" : "Removing deck…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .ignoresSafeArea()
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
                "Something went wrong",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )
            ) {
                Button("OK") { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "")
            }
            .confirmationDialog(
                "Remove \"\(deckPendingRemoval?.name ?? "")\"?",
                isPresented: Binding(
                    get: { deckPendingRemoval != nil },
                    set: { if !$0 { deckPendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Deck", role: .destructive) {
                    if let deck = deckPendingRemoval {
                        removeDeck(deck)
                    }
                    deckPendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    deckPendingRemoval = nil
                }
            } message: {
                Text("This permanently deletes this deck's cards, and any notes or media not shared with another deck. You can re-import the .apkg file later if you change your mind.")
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
            importDeck(from: url)
        }
    }

    /// Runs the (potentially slow, file-I/O-heavy) import against a
    /// background `ModelContext` on the same container, so the main thread
    /// -- and the progress indicator -- stay responsive. Results are
    /// resolved back into the main context by `PersistentIdentifier` once
    /// the background context has saved.
    private func importDeck(from url: URL) {
        isImporting = true
        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let backgroundContext = ModelContext(container)
            do {
                let importResult = try ApkgImporter.importApkg(fileURL: url, modelContext: backgroundContext)
                await MainActor.run {
                    isImporting = false
                    pendingNoteTypeIDsNeedingMapping = importResult.noteTypesNeedingMapping
                    presentNextMappingPromptIfNeeded()
                }
            } catch let error as ApkgImportError {
                await MainActor.run {
                    isImporting = false
                    importErrorMessage = error.errorDescription
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importErrorMessage = ApkgImportError.damagedCollection.errorDescription
                }
            }
        }
    }

    /// Removal walks every card/note/media file for the deck and can take a
    /// moment for a large deck, so it runs against a background
    /// `ModelContext` the same way import does -- resolved by
    /// `PersistentIdentifier` rather than crossing the main-context `Deck`
    /// object into a background task.
    private func removeDeck(_ deck: Deck) {
        isRemoving = true
        let deckID = deck.persistentModelID
        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let backgroundContext = ModelContext(container)
            guard let backgroundDeck = backgroundContext.model(for: deckID) as? Deck else {
                await MainActor.run { isRemoving = false }
                return
            }
            do {
                try DeckRemover.remove(backgroundDeck, from: backgroundContext)
                await MainActor.run { isRemoving = false }
            } catch {
                await MainActor.run {
                    isRemoving = false
                    importErrorMessage = "Couldn't remove this deck. Please try again."
                }
            }
        }
    }

    /// Opens the mapping sheet for every note type this deck uses, mapped
    /// or not -- mapping is always editable, not just a one-time prompt.
    /// Editing here affects every other deck that shares the same note
    /// type (mapping is keyed by note type, not by deck).
    private func editMapping(for deck: Deck) {
        pendingNoteTypeIDsNeedingMapping = deck.allNoteTypes.map(\.persistentModelID)
        presentNextMappingPromptIfNeeded()
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
