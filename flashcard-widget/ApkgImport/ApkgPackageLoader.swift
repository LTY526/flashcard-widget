//
//  ApkgPackageLoader.swift
//  flashcard-widget
//
//  Opens the outer zip and picks out the real collection database bytes,
//  regardless of which container variant produced the file. Detection
//  prefers the modern containers over a legacy-named entry, and confirms
//  by content (SQLite vs zstd magic bytes) rather than trusting names --
//  a modern export ships a dummy stub `collection.anki2` right alongside
//  the real `collection.anki21b` (apkg-import spec).
//

import Foundation

struct ApkgPackage {
    let sqliteData: Data
    let zip: ZipArchiveReader
    let mediaMap: [String: String]
}

enum ApkgPackageLoader {
    private static let zstdMagic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]
    private static let sqliteMagic = Array("SQLite format 3\0".utf8)

    static func load(fileData: Data) throws -> ApkgPackage {
        let zip: ZipArchiveReader
        do {
            zip = try ZipArchiveReader(data: fileData)
        } catch {
            throw ApkgImportError.notAnApkg
        }

        // Modern exports are preferred when present, since a legacy-named
        // stub may coexist purely for old-client compatibility.
        let candidateOrder = ["collection.anki21b", "collection.anki21", "collection.anki2"]
        guard let entry = candidateOrder.compactMap({ zip.entry(named: $0) }).first else {
            throw ApkgImportError.notAnApkg
        }

        let rawBytes: Data
        do {
            rawBytes = try zip.contents(of: entry)
        } catch {
            throw ApkgImportError.damagedCollection
        }

        let sqliteData = try decompressIfNeeded(rawBytes)

        var mediaMap: [String: String] = [:]
        if let mediaEntry = zip.entry(named: "media"),
           let mediaData = try? zip.contents(of: mediaEntry),
           let json = try? JSONSerialization.jsonObject(with: mediaData) as? [String: String] {
            mediaMap = json
        }

        return ApkgPackage(sqliteData: sqliteData, zip: zip, mediaMap: mediaMap)
    }

    /// Probes actual bytes rather than the entry's filename: a zstd frame
    /// always starts with a fixed 4-byte magic number, a SQLite file always
    /// starts with a fixed 16-byte literal header. Anything else is damaged.
    private static func decompressIfNeeded(_ bytes: Data) throws -> Data {
        if bytes.starts(with: zstdMagic) {
            do {
                return try ZstdDecompressor.decompress(bytes)
            } catch {
                throw ApkgImportError.damagedCollection
            }
        }
        if bytes.starts(with: sqliteMagic) {
            return bytes
        }
        throw ApkgImportError.damagedCollection
    }
}
