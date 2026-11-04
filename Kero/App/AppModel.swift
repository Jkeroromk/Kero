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
    /// Add Games opens straight to Wi-Fi Transfer (the home screen's Wi-Fi Transfer button).
    var addGamesStartsWithWiFi = false
    var isShowingSettings = false
    var gamePendingDeletion: KeroGame?
    var gamePendingRename: KeroGame?
    var gamePendingCover: KeroGame?
    var renameText = ""
    var message: AppMessage?

    @ObservationIgnored var modelContext: ModelContext?
    /// Called just before a game is deleted, so screens showing it can step away first.
    @ObservationIgnored var gameWillBeDeleted: ((KeroGame) -> Void)?

    var isShowingSheet: Bool {
        return self.isShowingAddGames || self.isShowingSettings || self.gamePendingDeletion != nil || self.gamePendingRename != nil || self.gamePendingCover != nil || self.message != nil
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
        game.isNameCustom = true
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

        self.gameWillBeDeleted?(game)
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
        self.launch(game, restart: restart, loadingState: nil)
    }

    func play(_ game: KeroGame, loadingState slot: Int)
    {
        if let session = self.session, session.game.identifier == game.identifier
        {
            session.loadState(slot: slot, closesMenu: false)
            self.resumeNowPlaying()
            return
        }

        self.launch(game, restart: false, loadingState: slot)
    }

    private func launch(_ game: KeroGame, restart: Bool, loadingState slot: Int?)
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
            if let slot
            {
                // Queued now; the emulation thread loads it between frames, so the game starts from the state.
                session.loadState(slot: slot, closesMenu: false)
            }
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
        self.addGamesStartsWithWiFi = false
        self.isShowingAddGames = true
    }

    func showWiFiTransfer()
    {
        self.addGamesStartsWithWiFi = true
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

    func chooseCover(for game: KeroGame)
    {
        self.gamePendingCover = game
    }

    func removeCover(of game: KeroGame)
    {
        guard let modelContext else { return }
        KeroCovers.removeCover(of: game, context: modelContext)
    }

    func setCover(_ data: Data)
    {
        guard let game = self.gamePendingCover, let modelContext else { return }
        self.gamePendingCover = nil
        KeroCovers.setCustomCover(data, for: game, context: modelContext)
    }

    func saveNowPlaying(to slot: Int)
    {
        self.session?.save(to: slot)
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
