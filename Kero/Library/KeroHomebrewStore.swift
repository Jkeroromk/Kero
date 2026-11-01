//
//  KeroHomebrewStore.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Free homebrew games whose authors allow redistribution. Kero doesn't host them: each game
//  downloads from its author's own release, and the license and source are shown with it.
//

import SwiftData
import SwiftUI

import KeroEngine

struct KeroHomebrewGame: Decodable, Identifiable, Hashable
{
    var id: String
    var title: String
    var author: String
    var system: String
    var year: Int?
    var genre: String?
    var description: String
    var license: String
    var licenseURL: String?
    var sourceURL: String?
    var homepage: String?
    var downloadURL: String
    var downloadIsZip: Bool?
    var sha1: String?
    var attribution: String?

    var keroSystem: KeroSystem {
        switch self.system.lowercased()
        {
        case "gbc": return .gameBoyColor
        case "gb": return .gameBoy
        default: return .gameBoyAdvance
        }
    }

    private enum CodingKeys: String, CodingKey
    {
        case id, title, author, system, year, genre, description, license, attribution, sha1
        case licenseURL = "license_url"
        case sourceURL = "source_url"
        case homepage
        case downloadURL = "download_url"
        case downloadIsZip = "download_is_zip"
    }
}

enum KeroHomebrewCatalog
{
    /// Bundled with the app (Resources/Homebrew.json); only titles that have been checked by hand.
    static let games: [KeroHomebrewGame] = {
        guard let url = Bundle.main.url(forResource: "Homebrew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([KeroHomebrewGame].self, from: data)
        else { return [] }
        return games
    }()
}

struct KeroHomebrewStoreView: View
{
    @Environment(AppModel.self) private var appModel
    @Query private var library: [KeroGame]

    @State private var downloads: [String: DownloadState] = [:]

    enum DownloadState: Equatable
    {
        case downloading
        case failed(String)
    }

    var body: some View
    {
        List {
            Section {
                ForEach(KeroHomebrewCatalog.games) { game in
                    KeroHomebrewRow(game: game,
                                    isInstalled: self.isInstalled(game),
                                    state: self.downloads[game.id]) {
                        self.download(game)
                    }
                }
            } footer: {
                Text("These games are made by independent developers who share them for free. Each one downloads from its author's own page; tap a game's license to see the terms.")
            }
        }
        .navigationTitle("Free Homebrew")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isInstalled(_ game: KeroHomebrewGame) -> Bool
    {
        if let sha1 = game.sha1?.lowercased(), self.library.contains(where: { $0.identifier.lowercased() == sha1 })
        {
            return true
        }
        return self.library.contains { $0.name == game.title }
    }

    private func download(_ game: KeroHomebrewGame)
    {
        guard let url = URL(string: game.downloadURL), self.downloads[game.id] != .downloading else { return }
        self.downloads[game.id] = .downloading

        Task {
            do
            {
                let (temporary, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode)
                {
                    throw URLError(.badServerResponse)
                }

                // Give the file a name Kero recognises (the game's title, with the right extension).
                let fileExtension = (game.downloadIsZip ?? false) ? "zip" : self.romExtension(for: game)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(game.title.replacingOccurrences(of: "/", with: "-")).appendingPathExtension(fileExtension)
                try FileManager.default.moveItem(at: temporary, to: destination)

                let result = await self.appModel.importFiles([destination])
                try? FileManager.default.removeItem(at: folder)

                if result.imported.isEmpty && result.duplicates.isEmpty
                {
                    self.downloads[game.id] = .failed(result.failures.first?.reason ?? "Couldn't add this game.")
                }
                else
                {
                    // Use the catalog title rather than whatever was in the file.
                    if let added = result.imported.first
                    {
                        added.name = game.title
                        try? self.appModel.modelContext?.save()
                    }
                    self.downloads[game.id] = nil
                }
            }
            catch
            {
                self.downloads[game.id] = .failed(error.localizedDescription)
            }
        }
    }

    private func romExtension(for game: KeroHomebrewGame) -> String
    {
        switch game.keroSystem
        {
        case .gameBoyColor: return "gbc"
        case .gameBoy: return "gb"
        default: return "gba"
        }
    }
}

private struct KeroHomebrewRow: View
{
    let game: KeroHomebrewGame
    let isInstalled: Bool
    let state: KeroHomebrewStoreView.DownloadState?
    let onGet: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View
    {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                KeroCoverPlaceholder(system: self.game.keroSystem, name: self.game.title)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.game.title)
                        .font(.headline)
                    Text(self.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                self.getButton
            }

            Text(self.game.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                if let license = self.game.licenseURL.flatMap(URL.init(string:))
                {
                    Button(self.game.license) { self.openURL(license) }
                }
                else
                {
                    Text(self.game.license)
                }

                if let source = (self.game.homepage ?? self.game.sourceURL).flatMap(URL.init(string:))
                {
                    Button("Author's Page") { self.openURL(source) }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)

            if let attribution = self.game.attribution
            {
                Text(attribution)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if case .failed(let reason) = self.state
            {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        var parts = [self.game.author, self.game.keroSystem.name]
        if let year = self.game.year { parts.append(String(year)) }
        if let genre = self.game.genre { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var getButton: some View
    {
        if self.isInstalled
        {
            Text("In Library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
        else if self.state == .downloading
        {
            ProgressView()
                .frame(width: 60)
        }
        else
        {
            Button(action: self.onGet) {
                Text("GET")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.borderless)
        }
    }
}
