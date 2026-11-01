//
//  KeroHomeModel.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  State for the console-style home screen: the game row, the focused game's
//  actions and the system buttons. Touch and controller input both go through here.
//

import SwiftUI

import KeroEngine

protocol KeroHomeHost: AnyObject
{
    var nowPlayingGame: KeroGame? { get }

    func launch(_ game: KeroGame, restart: Bool)
    func resumeNowPlaying()
    func showImport()
    func showSettings()
    func confirmDelete(_ game: KeroGame)
    func rename(_ game: KeroGame)
}

/// Which row has controller focus.
enum KeroHomeRow
{
    case games
    case actions
    case system
}

enum KeroGameAction: Hashable
{
    case play
    case restart
    case favorite
    case rename
    case delete
}

enum KeroSystemButton: String, CaseIterable, Identifiable
{
    case importGames
    case settings

    var id: String { self.rawValue }

    var title: String {
        switch self
        {
        case .importGames: return "Import"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self
        {
        case .importGames: return "plus"
        case .settings: return "gearshape.fill"
        }
    }
}

final class KeroHomeModel: ObservableObject
{
    @Published private(set) var games: [KeroGame] = []

    @Published var focusedGameIndex = 0
    @Published var row: KeroHomeRow = .games
    @Published var actionIndex = 0
    @Published var systemIndex = 0

    @Published var isControllerConnected = false
    /// Focus rings on buttons only show once a controller or keyboard is used.
    @Published var showsFocus = false

    @Published private(set) var nowPlayingGame: KeroGame?

    weak var host: KeroHomeHost?

    var focusedGame: KeroGame? {
        guard self.games.indices.contains(self.focusedGameIndex) else { return nil }
        return self.games[self.focusedGameIndex]
    }

    // MARK: Data

    /// Called by the view whenever the library changes.
    func update(games: [KeroGame])
    {
        // Most recently played first, then never-played games alphabetically.
        let sorted = games.sorted { lhs, rhs in
            switch (lhs.playedDate, rhs.playedDate)
            {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        let previousID = self.focusedGame?.identifier
        self.games = sorted

        if let previousID, let index = sorted.firstIndex(where: { $0.identifier == previousID })
        {
            self.focusedGameIndex = index
        }
        else
        {
            self.focusedGameIndex = 0
        }

        if sorted.isEmpty && self.row != .system
        {
            self.row = .system
            self.systemIndex = 0
        }

        self.refreshNowPlaying()
    }

    func refreshNowPlaying()
    {
        self.nowPlayingGame = self.host?.nowPlayingGame
    }

    func isRunning(_ game: KeroGame) -> Bool
    {
        return self.nowPlayingGame?.identifier == game.identifier
    }

    func actions(for game: KeroGame) -> [KeroGameAction]
    {
        var actions: [KeroGameAction] = [.play]
        if self.isRunning(game) { actions.append(.restart) }
        actions.append(.favorite)
        actions.append(.rename)
        actions.append(.delete)
        return actions
    }

    // MARK: Touch

    /// Tapping a card focuses it; tapping the focused card plays it.
    func tapGame(at index: Int)
    {
        guard self.games.indices.contains(index) else { return }

        if index == self.focusedGameIndex
        {
            KeroFeedback.select()
            self.perform(.play, for: self.games[index])
        }
        else
        {
            KeroFeedback.move()
            withAnimation(KeroTheme.focusSpring) {
                self.focusedGameIndex = index
                self.row = .games
            }
        }
    }

    func perform(_ action: KeroGameAction, for game: KeroGame)
    {
        switch action
        {
        case .play:
            if self.isRunning(game) { self.host?.resumeNowPlaying() }
            else { self.host?.launch(game, restart: false) }

        case .restart:
            self.host?.launch(game, restart: true)

        case .favorite:
            game.isFavorite.toggle()
            try? game.modelContext?.save()
            self.objectWillChange.send()
            KeroFeedback.tap()

        case .rename:
            self.host?.rename(game)

        case .delete:
            self.host?.confirmDelete(game)
        }
    }

    func perform(_ button: KeroSystemButton)
    {
        switch button
        {
        case .importGames: self.host?.showImport()
        case .settings: self.host?.showSettings()
        }
    }
}

// MARK: - Controller -

extension KeroHomeModel
{
    func handle(_ command: KeroCommand)
    {
        if !self.showsFocus
        {
            withAnimation(.easeOut(duration: 0.2)) { self.showsFocus = true }
        }

        if command == .resume
        {
            if self.nowPlayingGame != nil { self.host?.resumeNowPlaying() }
            return
        }

        withAnimation(KeroTheme.focusSpring) {
            switch self.row
            {
            case .games: self.handleGames(command)
            case .actions: self.handleActions(command)
            case .system: self.handleSystem(command)
            }
        }
    }

    private func handleGames(_ command: KeroCommand)
    {
        guard let game = self.focusedGame else {
            self.row = .system
            return
        }

        switch command
        {
        case .left: self.moveGame(by: -1)
        case .right: self.moveGame(by: 1)
        case .pageUp: self.moveGame(by: -5)
        case .pageDown: self.moveGame(by: 5)
        case .down:
            self.row = .actions
            self.actionIndex = 0
            KeroFeedback.move()
        case .confirm:
            KeroFeedback.select()
            self.perform(.play, for: game)
        case .action:
            self.perform(.favorite, for: game)
        case .up, .back, .resume:
            break
        }
    }

    private func handleActions(_ command: KeroCommand)
    {
        guard let game = self.focusedGame else {
            self.row = .system
            return
        }

        let actions = self.actions(for: game)
        self.actionIndex = min(self.actionIndex, actions.count - 1)

        switch command
        {
        case .left: self.moveIndex(&self.actionIndex, by: -1, count: actions.count)
        case .right: self.moveIndex(&self.actionIndex, by: 1, count: actions.count)
        case .up, .back:
            self.row = .games
            KeroFeedback.move()
        case .down:
            self.row = .system
            KeroFeedback.move()
        case .confirm:
            KeroFeedback.select()
            self.perform(actions[self.actionIndex], for: game)
        case .action:
            self.perform(.favorite, for: game)
        case .pageUp, .pageDown, .resume:
            break
        }
    }

    private func handleSystem(_ command: KeroCommand)
    {
        let count = KeroSystemButton.allCases.count

        switch command
        {
        case .left: self.moveIndex(&self.systemIndex, by: -1, count: count)
        case .right: self.moveIndex(&self.systemIndex, by: 1, count: count)
        case .up, .back:
            guard !self.games.isEmpty else { return }
            self.row = .actions
            KeroFeedback.move()
        case .confirm:
            KeroFeedback.select()
            self.perform(KeroSystemButton.allCases[self.systemIndex])
        case .down, .action, .pageUp, .pageDown, .resume:
            break
        }
    }

    private func moveGame(by delta: Int)
    {
        self.moveIndex(&self.focusedGameIndex, by: delta, count: self.games.count)
    }

    private func moveIndex(_ index: inout Int, by delta: Int, count: Int)
    {
        guard count > 0 else { return }

        let newIndex = min(max(index + delta, 0), count - 1)
        if newIndex == index
        {
            KeroFeedback.bump()
        }
        else
        {
            index = newIndex
            KeroFeedback.move()
        }
    }
}
