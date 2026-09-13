//
//  flashcard_widgetApp.swift
//  flashcard-widget
//
//  Created by User on 9/12/26.
//

import SwiftUI
import SwiftData

@main
struct flashcard_widgetApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Deck.self,
            NoteType.self,
            NoteTypeField.self,
            Note.self,
            Card.self,
            MediaItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
