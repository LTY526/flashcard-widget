//
//  ZstdDecompressor.swift
//  flashcard-widget
//
//  Thin Swift wrapper around the vendored zstd decompression-only C library
//  (see ThirdParty/zstd). `.anki21b` collection containers -- the format
//  most current Anki exports actually produce -- are zstd frames, and
//  Apple's Compression framework has no zstd algorithm, hence the vendored
//  dependency (ADR 0001).
//

import Foundation

enum ZstdDecompressorError: Error {
    case decodeFailed(String)
}

enum ZstdDecompressor {
    /// Decompresses a single zstd frame using a streaming context, so it
    /// works even for frames that don't advertise their decompressed size
    /// up front. Throws if the frame is corrupt or truncated.
    static func decompress(_ input: Data) throws -> Data {
        guard let dctx = ZSTD_createDCtx() else {
            throw ZstdDecompressorError.decodeFailed("failed to create ZSTD_DCtx")
        }
        defer { ZSTD_freeDCtx(dctx) }

        let chunkSize = max(1 << 16, Int(ZSTD_DStreamOutSize()))
        var outputBuffer = [UInt8](repeating: 0, count: chunkSize)
        var output = Data()
        var frameComplete = false

        try input.withUnsafeBytes { (inputRaw: UnsafeRawBufferPointer) in
            var inBuffer = ZSTD_inBuffer(src: inputRaw.baseAddress, size: inputRaw.count, pos: 0)
            repeat {
                var stepError: Error?
                outputBuffer.withUnsafeMutableBytes { (outputRaw: UnsafeMutableRawBufferPointer) in
                    var outBuffer = ZSTD_outBuffer(dst: outputRaw.baseAddress, size: outputRaw.count, pos: 0)
                    let code = ZSTD_decompressStream(dctx, &outBuffer, &inBuffer)
                    if ZSTD_isError(code) != 0 {
                        stepError = ZstdDecompressorError.decodeFailed(String(cString: ZSTD_getErrorName(code)))
                        return
                    }
                    if outBuffer.pos > 0 {
                        output.append(outputRaw.bindMemory(to: UInt8.self).baseAddress!, count: outBuffer.pos)
                    }
                    frameComplete = (code == 0)
                }
                if let stepError { throw stepError }
            } while inBuffer.pos < inBuffer.size && !frameComplete
        }

        guard frameComplete else {
            throw ZstdDecompressorError.decodeFailed("truncated or incomplete zstd frame")
        }
        return output
    }
}
