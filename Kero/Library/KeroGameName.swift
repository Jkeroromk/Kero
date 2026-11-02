//
//  KeroGameName.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Turns ROM file names like "1986 - Pokemon - Emerald Version (USA, Europe) [!]" or
//  "0986_-_Pokemon_Emerald_(U)(TrainerTim)" into a readable title.
//

import Foundation

import KeroEngine

enum KeroGameName
{
    /// A clean display name from a file name, falling back to the title in the ROM header.
    static func displayName(fileName: String, romURL: URL?, system: KeroSystem) -> String
    {
        let cleaned = self.clean(fileName)
        if self.isMeaningful(cleaned) { return cleaned }

        if let romURL, let title = self.headerTitle(of: romURL, system: system), self.isMeaningful(title)
        {
            return title
        }

        // Nothing better: keep whatever is left, or the raw file name.
        return cleaned.isEmpty ? fileName : cleaned
    }

    /// Strips release numbers, region/dump tags and separators from a file name.
    static func clean(_ fileName: String) -> String
    {
        var name = fileName

        // "Pokemon_Emerald" / "Pokemon.Emerald.U" → spaces (only when the name has no real spaces).
        if !name.contains(" ")
        {
            name = name.replacingOccurrences(of: "_", with: " ")
            if name.filter({ $0 == "." }).count >= 2 { name = name.replacingOccurrences(of: ".", with: " ") }
        }
        else
        {
            name = name.replacingOccurrences(of: "_", with: " ")
        }

        // Region, language, revision and dump tags: (USA, Europe) (U) (Rev 1) [!] [b1] [T+Chi] …
        name = name.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s*【[^】]*】"#, with: " ", options: .regularExpression)

        // Collapse whitespace and stray separators at the ends.
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " -–_.,"))

        // Leading release numbers from ROM sets: "1986 - Title", "#123 - Title", "0986. Title".
        // A bare number with nothing after it ("1942") or without a separator ("4 in 1") is kept.
        name = name.replacingOccurrences(of: #"^#?\d{1,5}\s*[-–]\s*(?=\S)"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"^#?\d{3,5}\.\s+(?=\S)"#, with: "", options: .regularExpression)

        // "Legend of Zelda, The - Minish Cap" → "The Legend of Zelda - Minish Cap"
        if let range = name.range(of: #"^(.+?), (The|A|An)\b"#, options: .regularExpression)
        {
            let match = String(name[range])
            let parts = match.components(separatedBy: ", ")
            if parts.count == 2
            {
                name = parts[1] + " " + parts[0] + name[range.upperBound...]
            }
        }

        return name
    }

    /// A title is worth showing if it has at least two letters (any script) and isn't just a number.
    static func isMeaningful(_ name: String) -> Bool
    {
        let letters = name.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters >= 2
    }

    /// The internal title stored in the ROM header, title-cased ("POKEMON EMER" → "Pokemon Emer").
    static func headerTitle(of url: URL, system: KeroSystem) -> String?
    {
        let range: Range<Int>
        switch system
        {
        case .gameBoyAdvance: range = 0xA0 ..< 0xAC
        case .nintendoDS: range = 0x00 ..< 0x0C
        case .gameBoy, .gameBoyColor: range = 0x134 ..< 0x144
        default: return nil
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard (try? handle.seek(toOffset: UInt64(range.lowerBound))) != nil,
              let data = try? handle.read(upToCount: range.count), data.count == range.count
        else { return nil }

        let printable = data.prefix { $0 >= 0x20 && $0 < 0x7F }
        guard let raw = String(bytes: printable, encoding: .ascii) else { return nil }

        let title = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return title.lowercased().capitalized
    }
}
