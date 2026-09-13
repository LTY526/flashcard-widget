//
//  MediaItem.swift
//  flashcard-widget
//
//  A media file (image/audio) referenced by a note's field content. Files
//  are copied into app storage at import time; rendering them is out of
//  scope for this slice (apkg-import spec).
//

import Foundation
import SwiftData

@Model
final class MediaItem {
    /// The filename as referenced inside the note's field HTML/sound tag
    /// (e.g. "dog.mp3"), which is also the name Anki's `media` map used to
    /// locate the underlying zip entry.
    var ankiFilename: String = ""

    /// Path of the copied file, relative to this app's Application Support
    /// directory.
    var relativeStoragePath: String = ""

    var createdAt: Date = Date()

    var note: Note?

    init(ankiFilename: String, relativeStoragePath: String, note: Note?) {
        self.ankiFilename = ankiFilename
        self.relativeStoragePath = relativeStoragePath
        self.note = note
        self.createdAt = Date()
    }
}
