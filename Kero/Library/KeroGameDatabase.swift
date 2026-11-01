//
//  KeroGameDatabase.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Recognises imported games: official title, region, languages and which cover to fetch.
//  Data: No-Intro via libretro-database (CC BY-SA 4.0), built by Tools/metadata.
//
//  Matching, best first:
//   1. SHA-1 of the whole ROM (an exact, known dump)
//   2. GBA serial in the header ("BPRE" → FireRed). Fan translations and hacks usually keep it.
//   3. GB/GBC header title for a few popular games whose hacks keep it ("POKEMON_GLD")
//   4. The file name, cleaned, against known titles
//

import Foundation

import KeroEngine

struct KeroGameInfo: Equatable, Sendable
{
    enum Match: String, Sendable
    {
        /// The exact dump is known.
        case exact
        /// Same game, different file: a revision, a fan translation or a hack.
        case related
    }

    var title: String
    var chineseTitle: String?
    var region: String
    /// ISO 639-1 codes.
    var languages: [String]
    var serial: String?
    var boxart: String?
    var match: Match
    /// A Chinese fan translation (汉化): not a known dump, and Chinese in the file name or text.
    var isChineseTranslation: Bool
}

final class KeroGameDatabase: @unchecked Sendable
{
    static let shared = KeroGameDatabase()

    private struct Entry
    {
        var sha1: String
        var serial: String
        var title: String
        var region: String
        var languages: [String]
        var flags: Set<String>
        var boxart: String
    }

    private struct Table
    {
        var bySHA1: [String: Entry] = [:]
        var bySerial: [String: [Entry]] = [:]
        var byTitle: [String: [Entry]] = [:]
        var byNormalizedTitle: [String: [Entry]] = [:]
    }

    private let lock = NSLock()
    private var tables: [KeroSystem: Table] = [:]
    private lazy var chineseNames: [String: String] = Self.loadPairs("names-zh")
    private lazy var headerTitles: [String: String] = Self.loadPairs("header-titles")

    // MARK: Lookup

    /// Identifies a ROM. `fileName` is the original file name (without extension), used for fan translations
    /// and as a last resort.
    func info(sha1: String, romURL: URL, fileName: String, system: KeroSystem) -> KeroGameInfo?
    {
        let table = self.table(for: system)
        let fileHasChinese = Self.containsCJK(fileName) || Self.mentionsChinese(fileName)

        if let entry = table.bySHA1[sha1.lowercased()]
        {
            return self.makeInfo(entry, in: table, match: .exact, isChineseTranslation: false)
        }

        let header = Self.readHeader(of: romURL, system: system)

        var related: Entry?
        if let serial = header.serial, serial.count == 4
        {
            related = Self.best(table.bySerial[String(serial.prefix(3))] ?? [], preferRegionLetter: serial.last)
        }
        if related == nil, let headerTitle = header.title, let title = self.headerTitles[headerTitle]
        {
            related = Self.best(table.byTitle[title] ?? [])
        }
        if related == nil
        {
            let cleaned = Self.normalize(KeroGameName.clean(fileName))
            if !cleaned.isEmpty
            {
                related = Self.best(table.byNormalizedTitle[cleaned] ?? [])
            }
        }

        guard let related else { return nil }
        return self.makeInfo(related, in: table, match: .related, isChineseTranslation: fileHasChinese)
    }

    func coverURL(for boxart: String, system: KeroSystem) -> URL?
    {
        let folder: String
        switch system
        {
        case .gameBoyAdvance: folder = "Nintendo - Game Boy Advance"
        case .gameBoyColor: folder = "Nintendo - Game Boy Color"
        case .gameBoy: folder = "Nintendo - Game Boy"
        default: return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "thumbnails.libretro.com"
        components.path = "/\(folder)/Named_Boxarts/\(boxart).png"
        return components.url
    }

    private func makeInfo(_ entry: Entry, in table: Table, match: KeroGameInfo.Match, isChineseTranslation: Bool) -> KeroGameInfo
    {
        var languages = entry.languages
        if isChineseTranslation && !languages.contains("zh")
        {
            languages = ["zh"]
        }

        return KeroGameInfo(title: entry.title,
                            chineseTitle: self.chineseTitle(for: entry, in: table),
                            region: entry.region,
                            languages: languages,
                            serial: entry.serial.isEmpty ? nil : entry.serial,
                            boxart: entry.boxart.isEmpty ? nil : entry.boxart,
                            match: match,
                            isChineseTranslation: isChineseTranslation)
    }

    // MARK: Loading

    private func table(for system: KeroSystem) -> Table
    {
        self.lock.lock()
        defer { self.lock.unlock() }

        if let table = self.tables[system] { return table }

        let resource: String
        switch system
        {
        case .gameBoyAdvance: resource = "gba"
        case .gameBoyColor: resource = "gbc"
        case .gameBoy: resource = "gb"
        default: resource = ""
        }

        var table = Table()
        if let url = Bundle.main.url(forResource: resource, withExtension: "tsv"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true)
            {
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 7 else { continue }

                let entry = Entry(sha1: columns[0],
                                  serial: columns[1],
                                  title: columns[2],
                                  region: columns[3],
                                  languages: columns[4].split(separator: ",").map(String.init),
                                  flags: Set(columns[5].split(separator: ",").map(String.init)),
                                  boxart: columns[6])

                table.bySHA1[entry.sha1] = entry
                if entry.serial.count == 4 { table.bySerial[String(entry.serial.prefix(3)), default: []].append(entry) }
                table.byTitle[entry.title, default: []].append(entry)
                table.byNormalizedTitle[Self.normalize(entry.title), default: []].append(entry)
            }
        }

        self.tables[system] = table
        return table
    }

    private static func loadPairs(_ resource: String) -> [String: String]
    {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }

        var pairs: [String: String] = [:]
        for line in text.split(separator: "\n")
        {
            let columns = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if columns.count == 2 { pairs[columns[0]] = columns[1] }
        }
        return pairs
    }

    // MARK: Helpers

    /// Clean retail releases first, then the ROM's own region, then USA / World / Europe / Japan.
    private static func best(_ entries: [Entry], preferRegionLetter: Character? = nil) -> Entry?
    {
        let regionOrder = ["USA", "World", "Europe", "Japan"]

        return entries.min { lhs, rhs in
            func score(_ entry: Entry) -> (Int, Int, Int, Int)
            {
                let dirty = entry.flags.isDisjoint(with: ["beta", "proto", "demo", "unl", "hack"]) ? 0 : 1
                let sameRegion = (preferRegionLetter != nil && entry.serial.last == preferRegionLetter) ? 0 : 1
                let region = regionOrder.firstIndex(where: { entry.region.hasPrefix($0) }) ?? regionOrder.count
                let hasCover = entry.boxart.isEmpty ? 1 : 0
                return (dirty, sameRegion, region, hasCover)
            }
            return score(lhs) < score(rhs)
        }
    }

    /// Lowercased letters and digits only, so "Pokemon_Emerald" and "Pokémon: Emerald" compare equal.
    static func normalize(_ title: String) -> String
    {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
            .replacingOccurrences(of: "version", with: "")
    }

    /// The curated Chinese name. Japanese and European releases use their US counterpart's (same serial).
    private func chineseTitle(for entry: Entry, in table: Table) -> String?
    {
        if let name = self.chineseNames[entry.title] { return name }
        guard entry.serial.count == 4 else { return nil }

        for other in table.bySerial[String(entry.serial.prefix(3))] ?? []
        {
            if let name = self.chineseNames[other.title] { return name }
        }
        return nil
    }

    static func containsCJK(_ text: String) -> Bool
    {
        return text.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) || (0x3400 ... 0x4DBF).contains($0.value) }
    }

    static func mentionsChinese(_ text: String) -> Bool
    {
        let lowered = text.lowercased()
        return ["chinese", "(chs)", "(cht)", "[chs]", "[cht]", "t+chi", "t-chi", "汉化", "中文"].contains { lowered.contains($0) }
    }

    /// GBA: game code at 0xAC. GB/GBC: title at 0x134.
    private static func readHeader(of url: URL, system: KeroSystem) -> (serial: String?, title: String?)
    {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
        defer { try? handle.close() }

        func ascii(at offset: UInt64, length: Int) -> String?
        {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: length), data.count == length
            else { return nil }
            let printable = data.prefix { $0 >= 0x20 && $0 < 0x7F }
            let text = String(decoding: printable, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }

        switch system
        {
        case .gameBoyAdvance:
            return (ascii(at: 0xAC, length: 4), ascii(at: 0xA0, length: 12))
        case .gameBoy, .gameBoyColor:
            // Newer GBC games put a 4-character code in the last bytes of the title; match the old 11-character form too.
            let full = ascii(at: 0x134, length: 16)
            let short = ascii(at: 0x134, length: 11)
            if let short, ["POKEMON_GLD", "POKEMON_SLV", "PM_CRYSTAL"].contains(short) { return (nil, short) }
            return (nil, full ?? short)
        default:
            return (nil, nil)
        }
    }
}
