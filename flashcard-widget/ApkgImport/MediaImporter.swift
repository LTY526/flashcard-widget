//
//  MediaImporter.swift
//  flashcard-widget
//
//  Copies media files referenced by a note's field content into app
//  storage and records them against the note. Rendering media is out of
//  scope for this slice; only the copy + association is required
//  (apkg-import spec).
//

import Foundation
import SwiftData

enum MediaImporter {
    static func copyReferencedMedia(for note: Note, package: ApkgPackage, modelContext: ModelContext) {
        guard !package.mediaMap.isEmpty else { return }
        let filenames = referencedFilenames(in: note.fieldValues)
        guard !filenames.isEmpty else { return }

        // Anki's `media` file maps zip-entry keys ("0", "1", ...) to their
        // original filenames; we need the reverse lookup.
        let zipKeyByFilename = Dictionary(uniqueKeysWithValues: package.mediaMap.map { ($1, $0) })

        for filename in filenames {
            if note.mediaItems.contains(where: { $0.ankiFilename == filename }) { continue }
            guard let zipKey = zipKeyByFilename[filename],
                  let entry = package.zip.entry(named: zipKey),
                  let data = try? package.zip.contents(of: entry) else { continue }

            let relativePath = "Media/\(zipKey)_\(sanitized(filename))"
            let destinationURL = storageDirectory().appendingPathComponent(relativePath)
            do {
                try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destinationURL)
            } catch {
                continue
            }

            let mediaItem = MediaItem(ankiFilename: filename, relativeStoragePath: relativePath, note: note)
            modelContext.insert(mediaItem)
            note.mediaItems.append(mediaItem)
        }
    }

    /// Anki field HTML/sound-tag syntax for referencing media:
    /// `[sound:file.mp3]` and `<img src="file.jpg">`.
    private static func referencedFilenames(in fieldValues: [String]) -> Set<String> {
        var result = Set<String>()
        let patterns = [
            "\\[sound:([^\\]]+)\\]",
            "<img[^>]+src=[\"']([^\"']+)[\"']",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for value in fieldValues {
                let range = NSRange(value.startIndex..., in: value)
                for match in regex.matches(in: value, range: range) where match.numberOfRanges > 1 {
                    if let r = Range(match.range(at: 1), in: value) {
                        result.insert(String(value[r]))
                    }
                }
            }
        }
        return result
    }

    private static func sanitized(_ filename: String) -> String {
        filename.replacingOccurrences(of: "/", with: "_")
    }

    static func storageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ApkgMedia", isDirectory: true)
    }
}
