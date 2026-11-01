//
//  KeroHomeModel.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  State for the home screen: which tiles exist, which one is focused,
//  and whether a game card ("LiveArea") is open. Touch and controller input
//  both funnel through here so they always agree on what is selected.
//

import SwiftUI
import SwiftData

import KeroEngine

protocol KeroHomeHost: AnyObject
{
    var nowPlayingGame: KeroGame? { get }

    func launch(_ game: KeroGame, restart: Bool)
    func resumeNowPlaying()
    func showImport()
    func showSettings()
    func confirmDelete(_ game: KeroGame)
}

enum KeroBuiltInApp: String, CaseIterable
{
    case importGames
    case settings

    var title: String {
        switch self
        {
        case .importGames: return NSLocalizedString("Import", comment: "")
        case .settings: return NSLocalizedString("Settings", comment: "")
        }
    }

    var symbolName: String {
        switch self
        {
        case .importGames: return "plus"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self
        {
        case .importGames: return Color(red: 0.13, green: 0.75, blue: 0.40)
        case .settings: return Color(red: 0.45, green: 0.52, blue: 0.62)
        }
    }
}

enum KeroTile: Identifiable, Equatable
{
    case app(KeroBuiltInApp)
    case game(KeroGame)

    var id: String {
        switch self
        {
        case .app(let app): return "app." + app.rawValue
        case .game(let game): return "game." + game.identifier
        }
    }

    static func ==(lhs: KeroTile, rhs: KeroTile) -> Bool
    {
        return lhs.id == rhs.id
    }
}

enum KeroLiveAreaButton: Int, CaseIterable
{
    case start
    case restart
    case favorite
    case delete
}

final class KeroHomeModel: ObservableObject
{
    @Published private(set) var tiles: [KeroTile] = []
    @Published private(set) var gameCount: Int = 0

    @Published var focusedIndex: Int = 0
    @Published private(set) var page: Int = 0

    /// Number of bubbles per row / rows per page, kept in sync with the current layout by the view.
    @Published var columns: Int = 4
    @Published var rowsPerPage: Int = 3

    @Published var liveAreaGame: KeroGame?
    @Published var liveAreaFocus: KeroLiveAreaButton = .start

    @Published var isControllerConnected: Bool = false
    @Published private(set) var nowPlayingGame: KeroGame?

    /// True once the user has used a controller, so focus rings show only when they matter.
    @Published var showsFocus: Bool = false

    weak var host: KeroHomeHost?

    private var games: [KeroGame] = []

    init()
    {
        self.rebuildTiles()
    }

    /// Called by the view whenever the SwiftData query changes.
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

        guard sorted.map(\.identifier) != self.games.map(\.identifier) || sorted.map(\.isFavorite) != self.games.map(\.isFavorite) else { return }

        self.games = sorted
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            self.rebuildTiles()
        }
    }

    // MARK: Derived

    var tilesPerPage: Int {
        return max(1, self.columns * self.rowsPerPage)
    }

    var pageCount: Int {
        return max(1, Int(ceil(Double(self.tiles.count) / Double(self.tilesPerPage))))
    }

    func tiles(onPage page: Int) -> ArraySlice<KeroTile>
    {
        let start = page * self.tilesPerPage
        let end = min(self.tiles.count, start + self.tilesPerPage)
        guard start < end else { return [] }
        return self.tiles[start..<end]
    }

    var focusedTile: KeroTile? {
        guard self.tiles.indices.contains(self.focusedIndex) else { return nil }
        return self.tiles[self.focusedIndex]
    }

    func refreshNowPlaying()
    {
        self.nowPlayingGame = self.host?.nowPlayingGame
    }

    /// Called when the user swipes the grid to another page with touch.
    func pageDidScroll(to page: Int)
    {
        guard page != self.page, page >= 0, page < self.pageCount else { return }

        self.page = page

        let pageRange = (page * self.tilesPerPage) ..< min(self.tiles.count, (page + 1) * self.tilesPerPage)
        if !pageRange.contains(self.focusedIndex)
        {
            self.focusedIndex = pageRange.lowerBound
        }
    }

    func layoutDidChange(columns: Int, rows: Int)
    {
        guard columns != self.columns || rows != self.rowsPerPage else { return }

        self.columns = max(1, columns)
        self.rowsPerPage = max(1, rows)
        self.updatePage()
    }
}

// MARK: - Actions -

extension KeroHomeModel
{
    func select(_ tile: KeroTile)
    {
        if let index = self.tiles.firstIndex(of: tile)
        {
            self.focusedIndex = index
            self.updatePage()
        }

        switch tile
        {
        case .app(.importGames): self.host?.showImport()
        case .app(.settings): self.host?.showSettings()
        case .game(let game): self.openLiveArea(for: game)
        }
    }

    func openLiveArea(for game: KeroGame)
    {
        self.liveAreaFocus = .start
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            self.liveAreaGame = game
        }
    }

    func closeLiveArea()
    {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            self.liveAreaGame = nil
        }
    }

    func isRunning(_ game: KeroGame) -> Bool
    {
        return self.nowPlayingGame?.identifier == game.identifier
    }

    func availableLiveAreaButtons(for game: KeroGame) -> [KeroLiveAreaButton]
    {
        var buttons: [KeroLiveAreaButton] = [.start]
        if self.isRunning(game) { buttons.append(.restart) }
        buttons.append(.favorite)
        buttons.append(.delete)
        return buttons
    }

    func perform(_ button: KeroLiveAreaButton, for game: KeroGame)
    {
        switch button
        {
        case .start:
            if self.isRunning(game)
            {
                self.host?.resumeNowPlaying()
            }
            else
            {
                self.host?.launch(game, restart: false)
            }

        case .restart:
            self.host?.launch(game, restart: true)

        case .favorite:
            self.toggleFavorite(game)

        case .delete:
            self.host?.confirmDelete(game)
        }
    }

    func toggleFavorite(_ game: KeroGame)
    {
        game.isFavorite.toggle()
        try? game.modelContext?.save()
        self.objectWillChange.send()
        KeroFeedback.tap()
    }
}

// MARK: - Controller -

extension KeroHomeModel
{
    func handle(_ command: KeroCommand)
    {
        if !self.showsFocus
        {
            // First controller press only reveals the focus ring, like a console waking up.
            withAnimation(.easeOut(duration: 0.2)) { self.showsFocus = true }
            if command.isDirectional { return }
        }

        if let game = self.liveAreaGame
        {
            self.handleLiveArea(command, game: game)
        }
        else
        {
            self.handleGrid(command)
        }
    }

    private func handleGrid(_ command: KeroCommand)
    {
        guard !self.tiles.isEmpty else { return }

        let columns = self.columns
        var index = self.focusedIndex

        switch command
        {
        case .left:
            index -= 1
        case .right:
            index += 1
        case .up:
            index -= columns
        case .down:
            // Moving down from the last row of a partially filled grid lands on the last tile.
            if index + columns < self.tiles.count
            {
                index += columns
            }
            else if (index / columns) < ((self.tiles.count - 1) / columns)
            {
                index = self.tiles.count - 1
            }
        case .pageUp:
            index -= self.tilesPerPage
        case .pageDown:
            index += self.tilesPerPage
        case .confirm:
            if let tile = self.focusedTile
            {
                KeroFeedback.select()
                self.select(tile)
            }
            return
        case .action:
            if case .game(let game)? = self.focusedTile
            {
                self.toggleFavorite(game)
            }
            return
        case .resume:
            if self.nowPlayingGame != nil
            {
                self.host?.resumeNowPlaying()
            }
            return
        case .back:
            return
        }

        index = min(max(index, 0), self.tiles.count - 1)
        guard index != self.focusedIndex else {
            KeroFeedback.bump()
            return
        }

        KeroFeedback.move()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            self.focusedIndex = index
            self.updatePage()
        }
    }

    private func handleLiveArea(_ command: KeroCommand, game: KeroGame)
    {
        let buttons = self.availableLiveAreaButtons(for: game)
        let current = buttons.firstIndex(of: self.liveAreaFocus) ?? 0

        switch command
        {
        case .left, .up:
            let next = max(0, current - 1)
            if next != current { KeroFeedback.move() }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { self.liveAreaFocus = buttons[next] }
        case .right, .down:
            let next = min(buttons.count - 1, current + 1)
            if next != current { KeroFeedback.move() }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { self.liveAreaFocus = buttons[next] }
        case .confirm:
            KeroFeedback.select()
            self.perform(buttons[current], for: game)
        case .action:
            self.toggleFavorite(game)
        case .back:
            self.closeLiveArea()
        case .resume:
            if self.isRunning(game) || self.nowPlayingGame == nil
            {
                self.perform(.start, for: game)
            }
            else
            {
                self.host?.resumeNowPlaying()
            }
        case .pageUp, .pageDown:
            break
        }
    }

    private func updatePage()
    {
        let page = self.focusedIndex / self.tilesPerPage
        if page != self.page
        {
            self.page = page
        }
    }
}

// MARK: - Data -

private extension KeroHomeModel
{
    func rebuildTiles()
    {
        let previousID = self.focusedTile?.id

        var tiles = [KeroTile]()
        tiles.append(.app(.importGames))
        tiles.append(contentsOf: self.games.map { KeroTile.game($0) })
        tiles.append(.app(.settings))

        self.tiles = tiles
        self.gameCount = self.games.count
        self.refreshNowPlaying()

        if let previousID, let index = tiles.firstIndex(where: { $0.id == previousID })
        {
            self.focusedIndex = index
        }
        else
        {
            // Default focus: the most recently played game, otherwise Import.
            self.focusedIndex = self.games.isEmpty ? 0 : 1
        }

        if let liveAreaGame = self.liveAreaGame, !self.games.contains(where: { $0.identifier == liveAreaGame.identifier })
        {
            self.liveAreaGame = nil
        }

        self.updatePage()
    }
}

// MARK: - Feedback -

enum KeroFeedback
{
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    static func move() { self.selection.selectionChanged() }
    static func select() { self.light.impactOccurred() }
    static func tap() { self.soft.impactOccurred() }
    static func bump() { self.rigid.impactOccurred(intensity: 0.4) }
}
