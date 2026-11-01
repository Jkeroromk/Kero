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

    /// Where iOS drops a copy of a file opened with "Open in Kero" (we don't open documents in place).
    static var inboxDirectory: URL {
        return URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Removes the Inbox copy iOS made for "Open in Kero", once it has been imported (or rejected).
    /// Files picked with the importer live elsewhere and are never touched.
    static func removeInboxCopy(_ url: URL)
    {
        let inbox = self.inboxDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let file = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard file.hasPrefix(inbox) else { return }

        try? FileManager.default.removeItem(atPath: file)
    }

    struct ImportResult
    {
        var imported: [KeroGame] = []
        var duplicates: [String] = []
        var failures: [(name: String, reason: String)] = []

        /// Alert-style summary, or nil when everything went fine.
        var summary: (title: String, text: String)? {
            var lines = [String]()
            if !self.duplicates.isEmpty
            {
                lines.append("Already in your library: " + self.duplicates.joined(separator: ", "))
            }
            for failure in self.failures
            {
                lines.append("\(failure.name): \(failure.reason)")
            }
            guard !lines.isEmpty else { return nil }

            let total = self.imported.count + self.duplicates.count + self.failures.count
            let title = self.imported.isEmpty ? "Nothing Imported" : "Imported \(self.imported.count) of \(total)"
            return (title, lines.joined(separator: "\n"))
        }
    }

    /// A game file staged in the temporary folder, ready to be added to the library.
    struct Candidate
    {
        var stagedURL: URL
        var name: String
        var system: KeroSystem
        var identifier: String
        var info: KeroGameInfo?
    }

    /// Copies games into the library: single files, whole folders and zip archives.
    /// The slow part (copying, unzipping, hashing) runs off the main thread.
    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext) async -> ImportResult
    {
        let staged = await Task.detached(priority: .userInitiated) {
            return self.stage(urls)
        }.value

        var result = ImportResult()
        result.failures = staged.failures

        try? FileManager.default.createDirectory(at: self.gamesDirectory, withIntermediateDirectories: true)

        var seen = Set<String>()
        for candidate in staged.candidates
        {
            defer { try? FileManager.default.removeItem(at: candidate.stagedURL) }

            let identifier = candidate.identifier
            let existing = FetchDescriptor<KeroGame>(predicate: #Predicate { $0.identifier == identifier })
            if seen.contains(identifier) || ((try? context.fetchCount(existing)) ?? 0) > 0
            {
                result.duplicates.append(candidate.name)
                continue
            }

            do
            {
                let fileName = identifier + "." + candidate.stagedURL.pathExtension.lowercased()
                let destination = self.gamesDirectory.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: destination.path)
                {
                    try FileManager.default.moveItem(at: candidate.stagedURL, to: destination)
                }

                let fileTitle = KeroGameName.displayName(fileName: candidate.name, romURL: destination, system: candidate.system)
                let game = KeroGame(identifier: identifier, name: fileTitle, fileName: fileName, system: candidate.system)
                game.fileTitle = fileTitle
                self.apply(candidate.info, to: game)
                context.insert(game)
                result.imported.append(game)
                seen.insert(identifier)
            }
            catch
            {
                result.failures.append((candidate.name, error.localizedDescription))
            }
        }

        try? context.save()

        KeroCovers.fetchMissing(for: result.imported, context: context)
        return result
    }

    // MARK: Game info

    static let metadataVersion = 1

    /// Fills in what the database knows about a game and picks its display name.
    @MainActor
    static func apply(_ info: KeroGameInfo?, to game: KeroGame)
    {
        game.officialTitle = info?.title
        game.chineseTitle = info?.chineseTitle
        game.region = info?.region
        game.languageCodes = info?.languages.joined(separator: ",")
        game.serial = info?.serial
        game.boxartName = info?.boxart
        game.isChineseTranslation = info?.isChineseTranslation ?? false
        game.metadataVersion = self.metadataVersion
        self.updateName(of: game)
    }

    /// "zh" or "en", from Settings (Automatic follows the iPhone's language).
    static var prefersChineseNames: Bool {
        switch UserDefaults.standard.string(forKey: "gameNameLanguage") ?? "auto"
        {
        case "zh": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    @MainActor
    static func updateName(of game: KeroGame)
    {
        guard !game.isNameCustom else { return }

        let fileTitle = game.fileTitle ?? game.name
        let fileTitleIsChinese = KeroGameDatabase.containsCJK(fileTitle)

        if self.prefersChineseNames
        {
            game.name = game.chineseTitle ?? (fileTitleIsChinese ? fileTitle : nil) ?? game.officialTitle ?? fileTitle
        }
        else
        {
            game.name = game.officialTitle ?? fileTitle
        }
    }

    /// After the name language changes in Settings.
    @MainActor
    static func updateNames(in context: ModelContext)
    {
        guard let games = try? context.fetch(FetchDescriptor<KeroGame>()) else { return }
        games.forEach { self.updateName(of: $0) }
        try? context.save()
    }

    /// Recognises games imported before the database existed (or by an older version of it), once.
    @MainActor
    static func refreshMetadata(in context: ModelContext) async
    {
        guard let games = try? context.fetch(FetchDescriptor<KeroGame>()) else { return }
        let stale = games.filter { $0.metadataVersion < self.metadataVersion }
        guard !stale.isEmpty else {
            KeroCovers.fetchMissing(for: games, context: context)
            return
        }

        let jobs = stale.map { (identifier: $0.identifier, romURL: $0.romURL, name: $0.fileTitle ?? $0.name, system: $0.system) }
        let infos = await Task.detached(priority: .utility) {
            jobs.map { KeroGameDatabase.shared.info(sha1: $0.identifier, romURL: $0.romURL, fileName: $0.name, system: $0.system) }
        }.value

        for (game, info) in zip(stale, infos)
        {
            if game.fileTitle == nil { game.fileTitle = game.name }
            self.apply(info, to: game)
        }
        try? context.save()

        KeroCovers.fetchMissing(for: games, context: context)
    }

    // MARK: Staging (background)

    private static let zipExtensions: Set<String> = ["zip"]

    private static func stage(_ urls: [URL]) -> (candidates: [Candidate], failures: [(name: String, reason: String)])
    {
        var candidates: [Candidate] = []
        var failures: [(name: String, reason: String)] = []

        func stageFile(_ url: URL, quietIfUnsupported: Bool)
        {
            let name = url.deletingPathExtension().lastPathComponent
            let pathExtension = url.pathExtension.lowercased()

            do
            {
                if self.zipExtensions.contains(pathExtension)
                {
                    let games = try self.stageZip(url)
                    if games.isEmpty
                    {
                        failures.append((url.lastPathComponent, "No Game Boy or GBA games inside."))
                    }
                    candidates.append(contentsOf: games)
                }
                else if let system = KeroCores.system(for: url)
                {
                    let staged = try self.coordinatedCopy(of: url)
                    let identifier = try KeroGameStorage.identifier(forROMAt: staged)
                    let info = KeroGameDatabase.shared.info(sha1: identifier, romURL: staged, fileName: name, system: system)
                    candidates.append(Candidate(stagedURL: staged, name: name, system: system, identifier: identifier, info: info))
                }
                else if !quietIfUnsupported
                {
                    failures.append((url.lastPathComponent, "Kero can't open .\(pathExtension.isEmpty ? "?" : pathExtension) files."))
                }
            }
            catch
            {
                failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }

        for url in urls
        {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
            {
                // Whole folder: pick up every game and zip inside, ignore everything else.
                let keys: [URLResourceKey] = [.isRegularFileKey]
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
                var found = 0
                while let file = enumerator?.nextObject() as? URL
                {
                    guard (try? file.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
                    let before = candidates.count
                    stageFile(file, quietIfUnsupported: true)
                    found += candidates.count - before
                }

                if found == 0 && failures.isEmpty
                {
                    failures.append((url.lastPathComponent, "No Game Boy or GBA games in this folder."))
                }
            }
            else
            {
                stageFile(url, quietIfUnsupported: false)
            }
        }

        return (candidates, failures)
    }

    /// Extracts every supported game from a zip into the temporary folder.
    private static func stageZip(_ url: URL) throws -> [Candidate]
    {
        let local = try self.coordinatedCopy(of: url)
        defer { try? FileManager.default.removeItem(at: local) }

        let archive = try KeroZipArchive(url: local)
        var candidates: [Candidate] = []

        for entry in archive.entries where !entry.isDirectory && !entry.path.hasPrefix("__MACOSX/") && !entry.fileName.hasPrefix(".")
        {
            let entryURL = URL(fileURLWithPath: entry.fileName)
            guard let system = KeroCores.system(for: entryURL) else { continue }

            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(entryURL.pathExtension)
            try archive.extract(entry, to: staged)

            let identifier = try KeroGameStorage.identifier(forROMAt: staged)
            let name = entryURL.deletingPathExtension().lastPathComponent
            let info = KeroGameDatabase.shared.info(sha1: identifier, romURL: staged, fileName: name, system: system)
            candidates.append(Candidate(stagedURL: staged, name: name, system: system, identifier: identifier, info: info))
        }

        return candidates
    }

    /// One-time cleanup of names imported before Kero tidied file names
    /// ("1986 - Pokemon - Emerald Version (USA, Europe)" → "Pokemon - Emerald Version").
    @MainActor
    static func tidyNames(in context: ModelContext)
    {
        let key = "KeroNameCleanupVersion"
        guard UserDefaults.standard.integer(forKey: key) < 1 else { return }

        if let games = try? context.fetch(FetchDescriptor<KeroGame>())
        {
            for game in games
            {
                let name = KeroGameName.displayName(fileName: game.name, romURL: game.romURL, system: game.system)
                if name != game.name { game.name = name }
            }
            try? context.save()
        }

        UserDefaults.standard.set(1, forKey: key)
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
