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

    var isShowingAddGames = false
    var isShowingSettings = false
    var gamePendingDeletion: KeroGame?
    var gamePendingRename: KeroGame?
    var renameText = ""
    var message: AppMessage?

    @ObservationIgnored var modelContext: ModelContext?

    var isShowingSheet: Bool {
        return self.isShowingAddGames || self.isShowingSettings || self.gamePendingDeletion != nil || self.gamePendingRename != nil || self.message != nil
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

    /// Number of import jobs running (shows a spinner in Add Games).
    var importsInProgress = 0

    /// Imports and returns the result, for callers that show it themselves (Add Games, Wi-Fi Transfer).
    @discardableResult
    func importFiles(_ urls: [URL]) async -> KeroLibrary.ImportResult
    {
        guard let modelContext, !urls.isEmpty else { return KeroLibrary.ImportResult() }

        self.importsInProgress += 1
        defer { self.importsInProgress -= 1 }

        return await KeroLibrary.importFiles(urls, into: modelContext)
    }

    /// Imports and reports problems in an alert ("Open in Kero", AirDrop).
    func importAndReport(_ urls: [URL], cleanup: (() -> Void)? = nil)
    {
        Task {
            let result = await self.importFiles(urls)
            cleanup?()

            if let summary = result.summary
            {
                self.message = AppMessage(title: summary.title, text: summary.text)
            }
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
        self.isShowingAddGames = true
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
