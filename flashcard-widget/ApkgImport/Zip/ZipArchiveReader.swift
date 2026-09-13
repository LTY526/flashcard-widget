//
//  ZipArchiveReader.swift
//  flashcard-widget
//
//  A minimal, independent reader for the subset of the ZIP file format
//  `.apkg` files use: it locates the End Of Central Directory record, walks
//  the central directory, and extracts entries that are either STORED or
//  DEFLATEd. This is a from-scratch reader against the public ZIP container
//  format -- it does not vendor or port unzip code from anywhere, let alone
//  from Anki. ZIP64 is intentionally not supported: `.apkg` decks are small
//  enough that no real-world file needs it.
//

import Compression
import Foundation

struct ZipEntry {
    let name: String
    let compressionMethod: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

enum ZipReaderError: Error {
    case notAZip
    case truncatedOrCorrupt
    case unsupportedCompressionMethod(UInt16)
}

struct ZipArchiveReader {
    private let data: Data
    let entries: [ZipEntry]

    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralDirectorySignature: UInt32 = 0x0201_4b50
    private static let localFileHeaderSignature: UInt32 = 0x0403_4b50

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.parseCentralDirectory(in: data)
    }

    func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    func contents(of entry: ZipEntry) throws -> Data {
        // The central directory's local-header offset only tells us where
        // the local header starts; the actual file data offset depends on
        // that local header's (possibly different) name/extra field
        // lengths, so we must read it rather than assume it matches the
        // central directory's copy.
        let bytes = [UInt8](data)
        var offset = entry.localHeaderOffset
        guard let signature = readUInt32LE(bytes, at: offset), signature == Self.localFileHeaderSignature else {
            throw ZipReaderError.truncatedOrCorrupt
        }
        guard let nameLength = readUInt16LE(bytes, at: offset + 26),
              let extraLength = readUInt16LE(bytes, at: offset + 28) else {
            throw ZipReaderError.truncatedOrCorrupt
        }
        offset += 30 + Int(nameLength) + Int(extraLength)

        guard offset + entry.compressedSize <= bytes.count else {
            throw ZipReaderError.truncatedOrCorrupt
        }
        let compressedBytes = Array(bytes[offset..<(offset + entry.compressedSize)])

        switch entry.compressionMethod {
        case 0: // stored
            return Data(compressedBytes)
        case 8: // deflate
            return try inflate(compressedBytes, uncompressedSize: entry.uncompressedSize)
        default:
            throw ZipReaderError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    // MARK: - Central directory parsing

    private static func parseCentralDirectory(in data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipReaderError.notAZip }

        // The EOCD record is fixed-size (22 bytes) plus a variable-length
        // comment (max 65535 bytes), so scan backwards from the end for its
        // signature.
        let searchFloor = max(0, bytes.count - 22 - 65535)
        var eocdOffset: Int?
        var i = bytes.count - 22
        while i >= searchFloor {
            if let sig = readUInt32LE(bytes, at: i), sig == eocdSignature {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocd = eocdOffset else { throw ZipReaderError.notAZip }

        guard let totalEntries = readUInt16LE(bytes, at: eocd + 10),
              let centralDirOffset = readUInt32LE(bytes, at: eocd + 16) else {
            throw ZipReaderError.truncatedOrCorrupt
        }

        var entries: [ZipEntry] = []
        var offset = Int(centralDirOffset)
        for _ in 0..<totalEntries {
            guard let sig = readUInt32LE(bytes, at: offset), sig == centralDirectorySignature else {
                throw ZipReaderError.truncatedOrCorrupt
            }
            guard let compressionMethod = readUInt16LE(bytes, at: offset + 10),
                  let compressedSize = readUInt32LE(bytes, at: offset + 20),
                  let uncompressedSize = readUInt32LE(bytes, at: offset + 24),
                  let nameLength = readUInt16LE(bytes, at: offset + 28),
                  let extraLength = readUInt16LE(bytes, at: offset + 30),
                  let commentLength = readUInt16LE(bytes, at: offset + 32),
                  let localHeaderOffset = readUInt32LE(bytes, at: offset + 42) else {
                throw ZipReaderError.truncatedOrCorrupt
            }

            let nameStart = offset + 46
            guard nameStart + Int(nameLength) <= bytes.count else {
                throw ZipReaderError.truncatedOrCorrupt
            }
            let nameBytes = Array(bytes[nameStart..<(nameStart + Int(nameLength))])
            let name = String(decoding: nameBytes, as: UTF8.self)

            entries.append(ZipEntry(
                name: name,
                compressionMethod: compressionMethod,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localHeaderOffset)
            ))

            offset = nameStart + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        return entries
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        Self.readUInt32LE(bytes, at: offset)
    }

    private func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        Self.readUInt16LE(bytes, at: offset)
    }

    // MARK: - DEFLATE decompression

    /// Apple's Compression framework names this algorithm "ZLIB" but it
    /// actually implements raw DEFLATE (RFC 1951, no zlib/RFC1950 wrapper)
    /// -- exactly what ZIP's compression method 8 stores. Verified against
    /// a known raw-deflate blob before relying on it here.
    private func inflate(_ compressedBytes: [UInt8], uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destination.deallocate() }

        let decodedCount = compressedBytes.withUnsafeBufferPointer { srcPtr -> Int in
            guard let srcBase = srcPtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destination, uncompressedSize,
                srcBase, compressedBytes.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard decodedCount == uncompressedSize else {
            throw ZipReaderError.truncatedOrCorrupt
        }
        return Data(bytes: destination, count: decodedCount)
    }
}
