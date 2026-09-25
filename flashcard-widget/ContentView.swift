//
//  ContentView.swift
//  flashcard-widget
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScheduleRefreshState {
    private(set) var revision = 0

    mutating func markRefreshed() {
        revision &+= 1
    }
}

struct ActivationGate {
    private enum State {
        case reconciling
        case failed
        case ready
    }

    private var state: State = .reconciling

    var blocksContent: Bool { state != .ready }
    var isReconciling: Bool { state == .reconciling }

    mutating func beginReconciliation() {
        state = .reconciling
    }

    mutating func reconciliationSucceeded() {
        state = .ready
    }

    mutating func reconciliationFailed() {
        state = .failed
    }
}

enum ImportOperation {
    static func run<Result>(
        _ operation: () throws -> Result,
        reload: () async -> Void
    ) async rethrows -> Result {
        let result = try operation()
        await reload()
        return result
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]

    @State private var isShowingFileImporter = false
    @State private var isImporting = false
    @State private var isRemoving = false
    @State private var activationGate = ActivationGate()
    @State private var importErrorMessage: String?
    @State private var noteTypeNeedingMapping: NoteType?
    @State private var pendingNoteTypeIDsNeedingMapping: [PersistentIdentifier] = []
    @State private var deckPendingRemoval: Deck?
    @State private var scheduleRefreshState = ScheduleRefreshState()
    @State private var route = DeckDetailRoute()
    @State private var pendingNextCoordinator = PendingNextCoordinator()
    @State private var onboardingSession: OnboardingSession?
    @State private var dismissedOnboardingKind: OnboardingPresentationKind?
    @State private var pendingAutomaticOnboarding = false

    private var apkgContentType: UTType {
        UTType(importedAs: "net.ankiweb.apkg", conformingTo: .zip)
    }

    private var otherModalIsActive: Bool {
        isShowingFileImporter || noteTypeNeedingMapping != nil ||
        importErrorMessage != nil || deckPendingRemoval != nil ||
        isImporting || isRemoving || pendingNextCoordinator.errorMessage != nil ||
        activationGate.blocksContent || !route.path.isEmpty
    }

    var body: some View {
        NavigationStack(path: $route.path) {
            VStack(spacing: 0) {
                // Temporary manual-test entry point. Keep through user review.
                Button("Test Onboarding") { presentManualOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)
                    .accessibilityHint("Opens the Getting Started guide for testing")
                if decks.isEmpty {
                    ContentUnavailableView(
                        "No decks yet",
                        systemImage: "rectangle.stack",
                        description: Text("Import an Anki .apkg file to get started.")
                    )
                } else {
                    List {
                        ForEach(decks) { deck in
                            NavigationLink(value: deck.ankiDeckID) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        HStack(spacing: 6) {
                                            Text(deck.name)
                                            if deck.isPaused {
                                                Text("Paused")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.secondary.opacity(0.2), in: Capsule())
                                            }
                                        }
                                        .foregroundStyle(deck.isPaused ? .secondary : .primary)
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
                            .swipeActions(edge: .leading) {
                                Button {
                                    togglePause(deck)
                                } label: {
                                    if deck.isPaused {
                                        Label("Resume", systemImage: "play.fill")
                                    } else {
                                        Label("Pause", systemImage: "pause.fill")
                                    }
                                }
                                .tint(deck.isPaused ? .green : .orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: Int64.self) { id in
                if let deck = deckForNavigation(id) {
                    DeckDetailView(
                        deck: deck,
                        route: $route,
                        coordinator: pendingNextCoordinator,
                        scheduleRevision: scheduleRefreshState.revision,
                        editMapping: editMapping
                    )
                } else {
                    ContentUnavailableView("Deck unavailable", systemImage: "rectangle.stack")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Getting Started") { presentManualOnboarding() }
                }
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
            .disabled(isImporting || isRemoving || activationGate.blocksContent)
            .overlay {
                if isImporting || isRemoving || activationGate.blocksContent {
                    ZStack {
                        Color.black.opacity(0.05)
                        if activationGate.isReconciling {
                            ProgressView("Updating schedule…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        } else if activationGate.blocksContent {
                            VStack(spacing: 12) {
                                Text("Schedule update failed")
                                    .font(.headline)
                                Button("Try Again") {
                                    activationGate.beginReconciliation()
                                    Task { await reconcileOnActivation() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            ProgressView(isImporting ? "Importing deck…" : "Removing deck…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
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
                FieldMappingView(noteType: noteType, coordinator: pendingNextCoordinator, onFinished: presentNextMappingPromptIfNeeded)
            }
        }
        .sheet(item: $onboardingSession, onDismiss: {
            // A swipe changes the binding without invoking a button callback.
            if let kind = dismissedOnboardingKind {
                finishOnboarding(.dismiss, kind: kind)
            }
        }) { session in
            OnboardingObservedDeckSource(session: session) { intent in
                finishOnboarding(intent, kind: session.kind)
            }
        }
        .overlay {
            if pendingNextCoordinator.errorMessage != nil {
                VStack(spacing: 12) {
                    Text(pendingNextCoordinator.errorMessage ?? "Schedule update failed")
                    Button("Retry") {
                        do { try pendingNextCoordinator.retry() }
                        catch { /* pending anchor stays available */ }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onOpenURL { url in
            route.requestDeepLink(DeckDeepLink.parse(url))
            if !activationGate.blocksContent { resolveRequestedDeepLink() }
        }
        .onChange(of: route.path) { oldPath, newPath in
            if oldPath.last != newPath.last {
                route.mode = .current
                route.scheduleTab = .upcoming
            }
            if newPath.isEmpty { schedulePendingOnboardingPresentation() }
        }
        .onChange(of: otherModalIsActive) { _, isActive in
            if !isActive { schedulePendingOnboardingPresentation() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            activationGate.beginReconciliation()
            Task { await reconcileOnActivation() }
        }
        .task {
            pendingNextCoordinator.configure(context: modelContext)
            if scenePhase == .active { await reconcileOnActivation() }
        }
    }

    private func reconcileOnActivation() async {
        do {
            try pendingNextCoordinator.retry()
            let lock = try ScheduleFileLock.shared()
            let changed = try await lock.withLock(mode: .exclusive) {
                let container = try SharedModelContainer.makeShared()
                let now = Date()
                return try DeckScheduler.reconcileOnActivation(in: container, now: now)
            }
            // No controls were interactive during reconciliation, so dropping
            // stale registered values is safe and forces the visible graph to
            // refetch the just-committed schedule.
            modelContext.rollback()
            modelContext.processPendingChanges()
            scheduleRefreshState.markRefreshed()
            if changed { await WidgetTimelineReloader.shared.scheduleReload() }
            activationGate.reconciliationSucceeded()
            resolveRequestedDeepLink()
            if onboardingSession == nil && OnboardingPersistence().shouldPresentAutomatically {
                pendingAutomaticOnboarding = true
                schedulePendingOnboardingPresentation()
            }
        } catch {
            activationGate.reconciliationFailed()
            importErrorMessage = "Couldn't update the schedule. Please try again."
        }
    }

    private func resolveRequestedDeepLink() {
        guard let id = route.requestedDeepLinkID else { return }
        do {
            let context = ModelContext(modelContext.container)
            var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.ankiDeckID == id })
            descriptor.fetchLimit = 1
            route.resolveRequestedDeepLink(exists: try !context.fetch(descriptor).isEmpty)
        } catch {
            importErrorMessage = "Couldn't open the deck. Please try again."
        }
    }

    private func deckForNavigation(_ id: Int64) -> Deck? {
        if let deck = decks.first(where: { $0.ankiDeckID == id }) { return deck }
        var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.ankiDeckID == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
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
        do { try pendingNextCoordinator.retry() }
        catch { return }
        isImporting = true
        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let backgroundContext = ModelContext(container)
            do {
                let importResult = try await ImportOperation.run({
                    try ApkgImporter.importApkg(fileURL: url, modelContext: backgroundContext)
                }, reload: {
                    // Import and re-import can replace cards and rebuild schedules.
                    // Invalidate WidgetKit only after the importer has committed the new graph.
                    await WidgetTimelineReloader.shared.scheduleReload()
                })
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
        do { try pendingNextCoordinator.flush(deckIDs: [deck.ankiDeckID]) }
        catch { return }
        isRemoving = true
        let deckID = deck.persistentModelID
        let ankiDeckID = deck.ankiDeckID
        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let backgroundContext = ModelContext(container)
            guard let backgroundDeck = backgroundContext.model(for: deckID) as? Deck else {
                await MainActor.run { isRemoving = false }
                return
            }
            do {
                try DeckRemover.remove(backgroundDeck, from: backgroundContext)
                await MainActor.run {
                    pendingNextCoordinator.cancelAfterDeletion(deckID: ankiDeckID)
                    isRemoving = false
                }
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

    /// Toggles a deck's pause state. Unpausing resumes normal queue
    /// maintenance immediately (rather than waiting for some later,
    /// unrelated read) by running the same top-up check any other
    /// schedule read performs.
    private func togglePause(_ deck: Deck) {
        do {
            try pendingNextCoordinator.performMutation(affectedDeckIDs: [deck.ankiDeckID]) {
                try ScheduleFileLock.shared().withExclusiveLock {
                    try DeckScheduler.setPaused(!deck.isPaused, deck: deck, in: modelContext, now: Date())
                    try modelContext.save()
                }
            }
            Task { await WidgetTimelineReloader.shared.scheduleReload() }
        } catch {
            modelContext.rollback()
            importErrorMessage = "Couldn't update the schedule. Please try again."
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

    private func presentManualOnboarding() {
        guard !otherModalIsActive, onboardingSession == nil else { return }
        // Manual replay never touches the version preference or library.
        pendingAutomaticOnboarding = false
        dismissedOnboardingKind = .manual
        onboardingSession = OnboardingSession(kind: .manual, initialStep: .importDeck)
    }

    private func schedulePendingOnboardingPresentation() {
        guard pendingAutomaticOnboarding else { return }
        // Let a picker, alert, or mapping sheet finish its dismissal animation.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard pendingAutomaticOnboarding, !otherModalIsActive,
                  onboardingSession == nil else { return }
            pendingAutomaticOnboarding = false
            dismissedOnboardingKind = .automatic
            onboardingSession = OnboardingSession(kind: .automatic, initialStep: .importDeck)
        }
    }

    private func finishOnboarding(_ intent: OnboardingIntent, kind: OnboardingPresentationKind) {
        OnboardingPersistence().handle(intent, presentation: kind)
        pendingAutomaticOnboarding = false
        dismissedOnboardingKind = nil
        onboardingSession = nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Deck.self, inMemory: true)
}
