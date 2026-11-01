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

    /// File types the importer offers. Extensions without a system UTI fall back to plain data.
    static var importableTypes: [UTType] {
        let extensions = KeroCores.supportedFileExtensions.sorted()
        let types = extensions.compactMap { UTType(filenameExtension: $0, conformingTo: .data) }
        return types + [.zip]
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

                let identifier = try KeroGameStorage.identifier(forROMAt: url)

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
                    try FileManager.default.copyItem(at: url, to: destination)
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
