//
//  KeroLibrary.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

import KeroEngine

enum KeroLibrary
{
    static var gamesDirectory: URL {
        return URL.applicationSupportDirectory.appendingPathComponent("Games", isDirectory: true)
    }

    static var artworkDirectory: URL {
        return URL.applicationSupportDirectory.appendingPathComponent("Artwork", isDirectory: true)
    }

    /// The picker accepts any file; `importFiles` decides what's a game by its extension.
    /// (Filtering by type in the picker greys out ROMs whenever iOS doesn't know the extension.)
    static var importableTypes: [UTType] {
        return [.item]
    }

    struct ImportResult
    {
        var imported: [KeroGame] = []
        var duplicates: [String] = []
        var failures: [(name: String, error: Error)] = []
    }

    /// Copies ROMs into the library. Files already in the library (same contents) are skipped.
    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext) -> ImportResult
    {
        var result = ImportResult()

        try? FileManager.default.createDirectory(at: self.gamesDirectory, withIntermediateDirectories: true)

        for url in urls
        {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let name = url.deletingPathExtension().lastPathComponent

            do
            {
                guard let system = KeroCores.system(for: url) else { throw KeroEngineError.unsupportedFile(url) }

                // Files in iCloud Drive may not be downloaded yet; a coordinated read fetches them.
                let localURL = try self.coordinatedCopy(of: url)
                defer { try? FileManager.default.removeItem(at: localURL) }

                let identifier = try KeroGameStorage.identifier(forROMAt: localURL)

                let existing = FetchDescriptor<KeroGame>(predicate: #Predicate { $0.identifier == identifier })
                if (try? context.fetchCount(existing)) ?? 0 > 0
                {
                    result.duplicates.append(name)
                    continue
                }

                let fileName = identifier + "." + url.pathExtension.lowercased()
                let destination = self.gamesDirectory.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: destination.path)
                {
                    try FileManager.default.copyItem(at: localURL, to: destination)
                }

                let game = KeroGame(identifier: identifier, name: name, fileName: fileName, system: system)
                context.insert(game)
                result.imported.append(game)
            }
            catch
            {
                result.failures.append((name, error))
            }
        }

        try? context.save()
        return result
    }

    /// Copies a (possibly cloud-only) file into a temporary location using NSFileCoordinator.
    private static func coordinatedCopy(of url: URL) throws -> URL
    {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            do
            {
                try FileManager.default.copyItem(at: readURL, to: temporaryURL)
            }
            catch
            {
                copyError = error
            }
        }

        if let error = coordinationError ?? copyError { throw error }
        return temporaryURL
    }

    @MainActor
    static func delete(_ game: KeroGame, from context: ModelContext)
    {
        try? FileManager.default.removeItem(at: game.romURL)
        if let artworkURL = game.artworkURL
        {
            try? FileManager.default.removeItem(at: artworkURL)
        }

        // Battery saves and save states are kept on purpose: re-importing the same ROM brings them back.
        context.delete(game)
        try? context.save()
    }
}
