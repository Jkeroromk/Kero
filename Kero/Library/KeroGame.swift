//
//  KeroGame.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import Foundation
import SwiftData

import KeroEngine

/// A game in the user's library. The ROM lives in the app's Games folder;
/// saves are stored by KeroEngine, keyed by `identifier` (SHA-1 of the ROM).
@Model
final class KeroGame
{
    @Attribute(.unique) var identifier: String
    var name: String
    var fileName: String
    var systemRawValue: Int
    var addedDate: Date
    var playedDate: Date?
    var isFavorite: Bool
    var artworkFileName: String?

    // Recognised from the game database (nil when the game isn't known).
    var officialTitle: String?
    var chineseTitle: String?
    var region: String?
    /// Comma-separated ISO 639-1 codes.
    var languageCodes: String?
    var serial: String?
    var boxartName: String?
    var isChineseTranslation: Bool = false
    /// Cleaned-up file name, kept for fan translations named in Chinese and as a fallback.
    var fileTitle: String?
    /// Set when the user renames the game; automatic names never override it.
    var isNameCustom: Bool = false
    var metadataVersion: Int = 0

    init(identifier: String, name: String, fileName: String, system: KeroSystem)
    {
        self.identifier = identifier
        self.name = name
        self.fileName = fileName
        self.systemRawValue = system.rawValue
        self.addedDate = Date()
        self.playedDate = nil
        self.isFavorite = false
        self.artworkFileName = nil
    }

    var system: KeroSystem {
        get { KeroSystem(rawValue: self.systemRawValue) ?? .gameBoyAdvance }
        set { self.systemRawValue = newValue.rawValue }
    }

    var romURL: URL {
        return KeroLibrary.gamesDirectory.appendingPathComponent(self.fileName)
    }

    var languages: [String] {
        return (self.languageCodes ?? "").split(separator: ",").map(String.init)
    }

    var artworkURL: URL? {
        guard let artworkFileName else { return nil }
        return KeroLibrary.artworkDirectory.appendingPathComponent(artworkFileName)
    }
}
