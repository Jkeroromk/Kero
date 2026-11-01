//
//  KeroZipArchive.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Minimal ZIP reader for importing games: reads the central directory and extracts
//  stored or deflated entries with Apple's Compression framework. No ZIP64, no encryption —
//  ROM archives don't need either.
//

import Compression
import Foundation

struct KeroZipArchive
{
    struct Entry
    {
        var path: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
        var isEncrypted: Bool

        var isDirectory: Bool { self.path.hasSuffix("/") }
        var fileName: String { (self.path as NSString).lastPathComponent }
    }

    enum ArchiveError: LocalizedError
    {
        case notAZip
        case unsupported(String)
        case corrupt

        var errorDescription: String? {
            switch self
            {
            case .notAZip: return "This isn't a zip file."
            case .unsupported(let reason): return "This zip file isn't supported (\(reason))."
            case .corrupt: return "This zip file is damaged."
            }
        }
    }

    /// Archives are memory-mapped; game archives are small (GBA ROMs top out at 32 MB).
    private let data: Data
    let entries: [Entry]

    init(url: URL) throws
    {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.entries = try Self.readCentralDirectory(self.data)
    }

    /// Extracts one entry to `destination`.
    func extract(_ entry: Entry, to destination: URL) throws
    {
        guard !entry.isEncrypted else { throw ArchiveError.unsupported("encrypted") }

        let offset = entry.localHeaderOffset
        guard self.data.count >= offset + 30, self.data.uint32(at: offset) == 0x04034b50 else { throw ArchiveError.corrupt }

        let nameLength = Int(self.data.uint16(at: offset + 26))
        let extraLength = Int(self.data.uint16(at: offset + 28))
        let start = offset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= self.data.count else { throw ArchiveError.corrupt }

        let compressed = self.data.subdata(in: start ..< start + entry.compressedSize)

        let output: Data
        switch entry.method
        {
        case 0:
            output = compressed

        case 8:
            output = try Self.inflate(compressed, expectedSize: entry.uncompressedSize)

        default:
            throw ArchiveError.unsupported("compression method \(entry.method)")
        }

        guard output.count == entry.uncompressedSize else { throw ArchiveError.corrupt }
        try output.write(to: destination, options: .atomic)
    }
}

private extension KeroZipArchive
{
    static func readCentralDirectory(_ data: Data) throws -> [Entry]
    {
        // End of central directory record: last 22 bytes + up to 64 KB of comment.
        guard data.count >= 22 else { throw ArchiveError.notAZip }

        let searchStart = max(0, data.count - 22 - 0xFFFF)
        var eocd: Int?
        var index = data.count - 22
        while index >= searchStart
        {
            if data.uint32(at: index) == 0x06054b50 { eocd = index; break }
            index -= 1
        }
        guard let eocd else { throw ArchiveError.notAZip }

        let count = Int(data.uint16(at: eocd + 10))
        let directoryOffset = Int(data.uint32(at: eocd + 16))
        guard count != 0xFFFF, directoryOffset != 0xFFFFFFFF else { throw ArchiveError.unsupported("ZIP64") }

        var entries: [Entry] = []
        var position = directoryOffset

        for _ in 0 ..< count
        {
            guard position + 46 <= data.count, data.uint32(at: position) == 0x02014b50 else { throw ArchiveError.corrupt }

            let flags = data.uint16(at: position + 8)
            let method = data.uint16(at: position + 10)
            let compressedSize = Int(data.uint32(at: position + 20))
            let uncompressedSize = Int(data.uint32(at: position + 24))
            let nameLength = Int(data.uint16(at: position + 28))
            let extraLength = Int(data.uint16(at: position + 30))
            let commentLength = Int(data.uint16(at: position + 32))
            let localOffset = Int(data.uint32(at: position + 42))

            guard position + 46 + nameLength <= data.count else { throw ArchiveError.corrupt }
            let nameData = data.subdata(in: position + 46 ..< position + 46 + nameLength)

            // Bit 11: UTF-8 names. Otherwise CP437 in theory, but most tools write UTF-8 or ASCII anyway.
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            entries.append(Entry(path: name,
                                 method: method,
                                 compressedSize: compressedSize,
                                 uncompressedSize: uncompressedSize,
                                 localHeaderOffset: localOffset,
                                 isEncrypted: flags & 0x1 != 0))

            position += 46 + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// Raw DEFLATE (what ZIP uses) via Compression's COMPRESSION_ZLIB.
    static func inflate(_ input: Data, expectedSize: Int) throws -> Data
    {
        guard expectedSize > 0 else { return Data() }

        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }

                return compression_decode_buffer(destinationBase, expectedSize, sourceBase, input.count, nil, COMPRESSION_ZLIB)
            }
        }

        guard written == expectedSize else { throw ArchiveError.corrupt }
        return output
    }
}

private extension Data
{
    func uint16(at offset: Int) -> UInt16
    {
        guard offset >= 0, offset + 2 <= self.count else { return 0 }
        let start = self.startIndex + offset
        return UInt16(self[start]) | UInt16(self[start + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32
    {
        guard offset >= 0, offset + 4 <= self.count else { return 0 }
        let start = self.startIndex + offset
        return UInt32(self[start]) | UInt32(self[start + 1]) << 8 | UInt32(self[start + 2]) << 16 | UInt32(self[start + 3]) << 24
    }
}
