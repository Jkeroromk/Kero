//
//  AppModel.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import Observation
import SwiftData
import SwiftUI

import KeroEngine

/// App-wide state: which game is running, and which sheets are showing.
@MainActor
@Observable
final class AppModel
{
    /// The game that's loaded (running or paused). Survives trips back to the home screen.
    private(set) var session: GameSession?

    /// True while the game screen is in front.
    var isPlaying = false

    var isImporting = false
    var isShowingSettings = false
    var gamePendingDeletion: KeroGame?
    var gamePendingRename: KeroGame?
    var renameText = ""
    var message: AppMessage?

    @ObservationIgnored var modelContext: ModelContext?

    var isShowingSheet: Bool {
        return self.isImporting || self.isShowingSettings || self.gamePendingDeletion != nil || self.gamePendingRename != nil || self.message != nil
    }

    func returnHome()
    {
        self.session?.suspend()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            self.isPlaying = false
        }
    }

    func quitGame()
    {
        self.session?.stop()
        self.session = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            self.isPlaying = false
        }
    }

    func handleImport(_ result: Result<[URL], Error>)
    {
        switch result
        {
        case .success(let urls): self.importFiles(urls)
        case .failure(let error): self.message = AppMessage(title: "Import Failed", text: error.localizedDescription)
        }
    }

    func importFiles(_ urls: [URL])
    {
        guard let modelContext else { return }

        let result = KeroLibrary.importFiles(urls, into: modelContext)

        var lines = [String]()
        if !result.duplicates.isEmpty
        {
            lines.append("Already in your library: " + result.duplicates.joined(separator: ", "))
        }
        for failure in result.failures
        {
            lines.append("\(failure.name): \(failure.error.localizedDescription)")
        }

        if !lines.isEmpty
        {
            let title = result.imported.isEmpty ? "Nothing Imported" : "Imported \(result.imported.count) of \(urls.count)"
            self.message = AppMessage(title: title, text: lines.joined(separator: "\n"))
        }
    }

    func commitRename()
    {
        guard let game = self.gamePendingRename else { return }
        self.gamePendingRename = nil

        let name = self.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != game.name else { return }

        game.name = name
        try? self.modelContext?.save()
    }

    func deletePendingGame()
    {
        guard let game = self.gamePendingDeletion, let modelContext else { return }
        self.gamePendingDeletion = nil

        if self.session?.game.identifier == game.identifier
        {
            self.quitGame()
        }

        KeroLibrary.delete(game, from: modelContext)
    }
}

extension AppModel: KeroHomeHost
{
    var nowPlayingGame: KeroGame? {
        return self.session?.game
    }

    func launch(_ game: KeroGame, restart: Bool)
    {
        if !restart, let session = self.session, session.game.identifier == game.identifier
        {
            self.resumeNowPlaying()
            return
        }

        self.session?.stop()
        self.session = nil

        do
        {
            let session = try GameSession(game: game)
            self.session = session

            game.playedDate = Date()
            try? self.modelContext?.save()

            session.start()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                self.isPlaying = true
            }
        }
        catch
        {
            self.message = AppMessage(title: "Couldn't Start \(game.name)", text: error.localizedDescription)
        }
    }

    func resumeNowPlaying()
    {
        guard let session else { return }

        session.resume()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            self.isPlaying = true
        }
    }

    func showImport()
    {
        self.isImporting = true
    }

    func showSettings()
    {
        self.isShowingSettings = true
    }

    func confirmDelete(_ game: KeroGame)
    {
        self.gamePendingDeletion = game
    }

    func rename(_ game: KeroGame)
    {
        self.renameText = game.name
        self.gamePendingRename = game
    }
}

struct AppMessage: Identifiable
{
    let id = UUID()
    var title: String
    var text: String
}
