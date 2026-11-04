//
//  KeroHomeModel.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  State behind the home screen, the library and game details: which screen is showing, what has
//  controller focus, and the library's filters. Touch and controller input both go through here.
//

import SwiftUI

import KeroEngine

@MainActor
protocol KeroHomeHost: AnyObject
{
    var nowPlayingGame: KeroGame? { get }

    func launch(_ game: KeroGame, restart: Bool)
    /// Starts (or switches to) the game and loads a save-state slot.
    func play(_ game: KeroGame, loadingState slot: Int)
    func resumeNowPlaying()
    func showImport()
    /// Add Games, opened straight to Wi-Fi Transfer.
    func showWiFiTransfer()
    func showSettings()
    func confirmDelete(_ game: KeroGame)
    func rename(_ game: KeroGame)
    func chooseCover(for game: KeroGame)
    func removeCover(of game: KeroGame)
    /// Saves the paused game into a slot (from game details, while that game is suspended).
    func saveNowPlaying(to slot: Int)
}

enum KeroHomeSection: Hashable
{
    case home
    case library
    case details
}

// MARK: Home

enum KeroHomeFocus: Hashable
{
    case shelf
    case hero(KeroHeroAction)
    case quickResume(Int)
    case dock(KeroDockButton)
}

enum KeroHeroAction: Hashable
{
    case play
    case restart
    case favorite
    case more
}

enum KeroDockButton: String, CaseIterable, Identifiable
{
    case library
    case addGames
    case wifiTransfer
    case settings

    var id: String { self.rawValue }

    var title: String {
        switch self
        {
        case .library: return "Library"
        case .addGames: return "Add Games"
        case .wifiTransfer: return "Wi-Fi Transfer"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self
        {
        case .library: return "square.grid.2x2"
        case .addGames: return "plus"
        case .wifiTransfer: return "wifi"
        case .settings: return "gearshape"
        }
    }
}

// MARK: Library

enum KeroLibraryFilter: Hashable
{
    case all
    case system(KeroSystem)
    case favorites
    case recentlyAdded
    case fanTranslations

    var title: String {
        switch self
        {
        case .all: return "All games"
        case .system(let system): return system.name
        case .favorites: return "Favorites"
        case .recentlyAdded: return "Recently added"
        case .fanTranslations: return "Fan translations"
        }
    }
}

enum KeroLibrarySort: String, CaseIterable, Identifiable
{
    case recentlyPlayed
    case name
    case recentlyAdded

    var id: String { self.rawValue }

    var title: String {
        switch self
        {
        case .recentlyPlayed: return "Recently played"
        case .name: return "Name"
        case .recentlyAdded: return "Recently added"
        }
    }
}

enum KeroRailItem: Hashable
{
    case filter(KeroLibraryFilter)
    case addGames
}

enum KeroLibraryFocus: Hashable
{
    case grid(Int)
    case rail(Int)
}

// MARK: Details

enum KeroDetailFocus: Hashable
{
    case play
    case loadLatest
    case favorite
    /// Index into `KeroSaveStates.allSlots`.
    case slot(Int)
}

// MARK: Outer display

enum KeroCompactFilter: Hashable
{
    case all
    case system(KeroSystem)
    /// Game Boy and Game Boy Color together.
    case gameBoyFamily

    var title: String {
        switch self
        {
        case .all: return "All"
        case .system(let system): return system.shortName
        case .gameBoyFamily: return "GB / GBC"
        }
    }

    func includes(_ system: KeroSystem) -> Bool
    {
        switch self
        {
        case .all: return true
        case .system(let filter): return filter == system
        case .gameBoyFamily: return system == .gameBoy || system == .gameBoyColor
        }
    }
}

// MARK: - Model -

@MainActor
final class KeroHomeModel: ObservableObject
{
    /// Every game, most recently played first, then the rest newest first.
    @Published private(set) var games: [KeroGame] = []

    @Published var section: KeroHomeSection = .home
    @Published private(set) var detailGameID: String?
    /// Where Back goes from game details.
    @Published private(set) var detailReturnsTo: KeroHomeSection = .library

    // Home
    @Published var focusedGameIndex = 0
    @Published var homeFocus: KeroHomeFocus = .shelf

    // Library
    @Published var libraryFilter: KeroLibraryFilter = .all
    @Published var librarySearch = ""
    @Published var librarySort: KeroLibrarySort = KeroLibrarySort(rawValue: UserDefaults.standard.string(forKey: "librarySort") ?? "") ?? .recentlyPlayed {
        didSet { UserDefaults.standard.set(self.librarySort.rawValue, forKey: "librarySort") }
    }
    @Published var libraryIsList = UserDefaults.standard.bool(forKey: "libraryIsList") {
        didSet { UserDefaults.standard.set(self.libraryIsList, forKey: "libraryIsList") }
    }
    @Published var libraryFocus: KeroLibraryFocus = .grid(0)
    /// Set by the library view from its width.
    var libraryColumns = 6

    // Details
    @Published var detailFocus: KeroDetailFocus = .play

    // Outer display
    /// Set by the home screen from the window width.
    @Published var isCompact = false
    @Published var compactFilter: KeroCompactFilter = .all
    /// -1 is the now-playing card's button, 0... the list.
    @Published var compactFocus = 0

    @Published var isControllerConnected = false
    /// Focus rings only show once a controller or keyboard is used.
    @Published var showsFocus = false

    @Published private(set) var nowPlayingGame: KeroGame?

    /// True while a text field (library search) has the keyboard, so typing doesn't move focus.
    var isTyping = false

    weak var host: KeroHomeHost?

    static let shelfLimit = 12

    // MARK: Derived

    var shelfGames: [KeroGame] {
        return Array(self.games.prefix(Self.shelfLimit))
    }

    var focusedGame: KeroGame? {
        let shelf = self.shelfGames
        guard shelf.indices.contains(self.focusedGameIndex) else { return shelf.first }
        return shelf[self.focusedGameIndex]
    }

    var detailGame: KeroGame? {
        guard let id = self.detailGameID else { return nil }
        return self.games.first { $0.identifier == id }
    }

    func isRunning(_ game: KeroGame) -> Bool
    {
        return self.nowPlayingGame?.identifier == game.identifier
    }

    func heroActions(for game: KeroGame) -> [KeroHeroAction]
    {
        return self.isRunning(game) ? [.play, .restart, .favorite, .more] : [.play, .favorite, .more]
    }

    func quickResumeStates(for game: KeroGame) -> [KeroSaveState]
    {
        return Array(KeroSaveStates.shared.states(for: game.identifier).prefix(3))
    }

    /// Systems in the library, in the order the rail lists them.
    var librarySystems: [KeroSystem] {
        let present = Set(self.games.map(\.system))
        let order: [KeroSystem] = [.nintendoDS, .gameBoyAdvance, .gameBoyColor, .gameBoy, .snes, .nes, .genesis]
        return order.filter { present.contains($0) }
    }

    var railItems: [KeroRailItem] {
        return [.filter(.all)] + self.librarySystems.map { .filter(.system($0)) }
            + [.filter(.favorites), .filter(.recentlyAdded), .filter(.fanTranslations), .addGames]
    }

    func count(for filter: KeroLibraryFilter) -> Int
    {
        return self.filteredGames(filter).count
    }

    func filteredGames(_ filter: KeroLibraryFilter) -> [KeroGame]
    {
        switch filter
        {
        case .all: return self.games
        case .system(let system): return self.games.filter { $0.system == system }
        case .favorites: return self.games.filter(\.isFavorite)
        case .recentlyAdded: return Array(self.games.sorted { $0.addedDate > $1.addedDate }.prefix(24))
        case .fanTranslations: return self.games.filter(\.isChineseTranslation)
        }
    }

    /// The library grid: filter, search, then sort.
    var libraryGames: [KeroGame] {
        var games = self.filteredGames(self.libraryFilter)

        let query = self.librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty
        {
            games = games.filter { game in
                [game.name, game.officialTitle, game.chineseTitle, game.fileTitle].contains { $0?.localizedStandardContains(query) == true }
            }
        }

        switch self.librarySort
        {
        case .recentlyPlayed: return games.sorted(by: Self.recentlyPlayedFirst)
        case .name: return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyAdded: return games.sorted { $0.addedDate > $1.addedDate }
        }
    }

    var compactFilters: [KeroCompactFilter] {
        let systems = self.librarySystems
        var filters: [KeroCompactFilter] = [.all]
        for system in systems where system != .gameBoy && system != .gameBoyColor
        {
            filters.append(.system(system))
        }
        if systems.contains(.gameBoy) || systems.contains(.gameBoyColor)
        {
            filters.append(.gameBoyFamily)
        }
        return filters
    }

    /// The outer display's card: the paused game, otherwise the last one played.
    var compactHeroGame: KeroGame? {
        if let nowPlaying = self.nowPlayingGame, let game = self.games.first(where: { $0.identifier == nowPlaying.identifier })
        {
            return game
        }
        return self.games.first { $0.playedDate != nil }
    }

    var compactGames: [KeroGame] {
        let hero = self.compactHeroGame?.identifier
        return self.games.filter { $0.identifier != hero && self.compactFilter.includes($0.system) }
    }

    private static func recentlyPlayedFirst(_ lhs: KeroGame, _ rhs: KeroGame) -> Bool
    {
        switch (lhs.playedDate, rhs.playedDate)
        {
        case let (l?, r?): return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.addedDate > rhs.addedDate
        }
    }

    // MARK: Data

    /// Called by the view whenever the library changes.
    func update(games: [KeroGame])
    {
        let previousID = self.focusedGame?.identifier
        let sorted = games.filter { !$0.isDeleted }.sorted(by: Self.recentlyPlayedFirst)
        self.games = sorted

        let shelf = self.shelfGames
        if let previousID, let index = shelf.firstIndex(where: { $0.identifier == previousID })
        {
            self.focusedGameIndex = index
        }
        else
        {
            self.focusedGameIndex = 0
        }

        if sorted.isEmpty
        {
            if case .dock = self.homeFocus {} else { self.homeFocus = .dock(.addGames) }
            if self.section == .details { self.section = .home }
        }

        if self.section == .details && self.detailGame == nil
        {
            self.section = self.detailReturnsTo
        }

        self.clampFocus()
        self.refreshNowPlaying()
    }

    /// Before a game is deleted: stop showing it, so nothing reads it after it's gone.
    func gameWillBeDeleted(_ game: KeroGame)
    {
        if self.detailGameID == game.identifier
        {
            self.section = self.detailReturnsTo
            self.detailGameID = nil
        }
        self.games.removeAll { $0.identifier == game.identifier }
        self.clampFocus()
    }

    func refreshNowPlaying()
    {
        let previous = self.nowPlayingGame?.identifier
        self.nowPlayingGame = self.host?.nowPlayingGame

        // Coming back from a game: put it in front.
        if let nowPlaying = self.nowPlayingGame, nowPlaying.identifier != previous,
           let index = self.shelfGames.firstIndex(where: { $0.identifier == nowPlaying.identifier })
        {
            self.focusedGameIndex = index
        }
    }

    private func clampFocus()
    {
        let shelfCount = self.shelfGames.count
        self.focusedGameIndex = min(max(0, self.focusedGameIndex), max(0, shelfCount - 1))

        if case .grid(let index) = self.libraryFocus
        {
            let count = self.libraryGames.count
            self.libraryFocus = count == 0 ? .rail(0) : .grid(min(index, count - 1))
        }

        self.compactFocus = min(self.compactFocus, self.compactGames.count - 1)
        if self.compactFocus < 0 && self.compactHeroGame == nil { self.compactFocus = 0 }
    }

    // MARK: Navigation

    func showHome()
    {
        withAnimation(.easeInOut(duration: 0.22)) { self.section = .home }
    }

    func showLibrary()
    {
        if case .grid = self.libraryFocus {} else if !self.libraryGames.isEmpty { self.libraryFocus = .grid(0) }
        withAnimation(.easeInOut(duration: 0.22)) { self.section = .library }
    }

    func openDetails(_ game: KeroGame)
    {
        self.detailReturnsTo = self.section == .details ? self.detailReturnsTo : self.section
        self.detailGameID = game.identifier
        self.detailFocus = .play
        withAnimation(.easeInOut(duration: 0.22)) { self.section = .details }
    }

    func closeDetails()
    {
        withAnimation(.easeInOut(duration: 0.22)) { self.section = self.detailReturnsTo }
    }

    // MARK: Actions

    /// Tapping a shelf cover shows it in the hero; tapping the one already shown plays it.
    func tapShelfGame(at index: Int)
    {
        let shelf = self.shelfGames
        guard shelf.indices.contains(index) else { return }

        if index == self.focusedGameIndex
        {
            KeroFeedback.select()
            self.play(shelf[index])
        }
        else
        {
            KeroFeedback.move()
            withAnimation(KeroTheme.focusSpring) {
                self.focusedGameIndex = index
                self.homeFocus = .shelf
            }
        }
    }

    func play(_ game: KeroGame)
    {
        if self.isRunning(game) { self.host?.resumeNowPlaying() }
        else { self.host?.launch(game, restart: false) }
    }

    func restart(_ game: KeroGame)
    {
        self.host?.launch(game, restart: true)
    }

    func load(_ state: KeroSaveState, of game: KeroGame)
    {
        KeroFeedback.select()
        self.host?.play(game, loadingState: state.slot)
    }

    func toggleFavorite(_ game: KeroGame)
    {
        game.isFavorite.toggle()
        try? game.modelContext?.save()
        self.objectWillChange.send()
        KeroFeedback.tap()
    }

    func perform(_ button: KeroDockButton)
    {
        switch button
        {
        case .library: self.showLibrary()
        case .addGames: self.host?.showImport()
        case .wifiTransfer: self.host?.showWiFiTransfer()
        case .settings: self.host?.showSettings()
        }
    }

    func perform(_ action: KeroHeroAction, for game: KeroGame)
    {
        switch action
        {
        case .play: self.play(game)
        case .restart: self.restart(game)
        case .favorite: self.toggleFavorite(game)
        // A controller can't open the menu behind "…", so it opens game details, which has the same actions.
        case .more: self.openDetails(game)
        }
    }

    func select(_ item: KeroRailItem)
    {
        switch item
        {
        case .filter(let filter):
            withAnimation(.easeInOut(duration: 0.2)) {
                self.libraryFilter = filter
                if case .grid = self.libraryFocus { self.libraryFocus = .grid(0) }
            }
        case .addGames:
            self.host?.showImport()
        }
    }
}

// MARK: - Controller -

extension KeroHomeModel
{
    func handle(_ command: KeroCommand)
    {
        guard !self.isTyping else { return }

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
            if self.isCompact && self.section != .details
            {
                self.handleCompact(command)
                return
            }

            switch self.section
            {
            case .home: self.handleHome(command)
            case .library: self.handleLibrary(command)
            case .details: self.handleDetails(command)
            }
        }
    }

    // MARK: Home

    private func handleHome(_ command: KeroCommand)
    {
        if command == .pageDown
        {
            self.showLibrary()
            return
        }

        guard let game = self.focusedGame else {
            // Empty library: only the dock.
            if case .dock(let button) = self.homeFocus { self.handleDock(command, button: button, hasGames: false) }
            else { self.homeFocus = .dock(.addGames) }
            return
        }

        switch self.homeFocus
        {
        case .shelf:
            switch command
            {
            case .left: self.move(&self.focusedGameIndex, by: -1, count: self.shelfGames.count)
            case .right: self.move(&self.focusedGameIndex, by: 1, count: self.shelfGames.count)
            case .up: self.homeFocus = .hero(.play); KeroFeedback.move()
            case .down: self.homeFocus = .dock(.library); KeroFeedback.move()
            case .confirm: KeroFeedback.select(); self.play(game)
            case .action: self.toggleFavorite(game)
            case .back, .pageUp, .pageDown, .resume: break
            }

        case .hero(let action):
            let actions = self.heroActions(for: game)
            var index = actions.firstIndex(of: action) ?? 0
            let states = self.quickResumeStates(for: game)

            switch command
            {
            case .left:
                self.move(&index, by: -1, count: actions.count)
                self.homeFocus = .hero(actions[index])
            case .right:
                if index == actions.count - 1, !states.isEmpty
                {
                    self.homeFocus = .quickResume(0)
                    KeroFeedback.move()
                }
                else
                {
                    self.move(&index, by: 1, count: actions.count)
                    self.homeFocus = .hero(actions[index])
                }
            case .down, .back: self.homeFocus = .shelf; KeroFeedback.move()
            case .confirm: KeroFeedback.select(); self.perform(actions[index], for: game)
            case .action: self.toggleFavorite(game)
            case .up, .pageUp, .pageDown, .resume: break
            }

        case .quickResume(var index):
            let states = self.quickResumeStates(for: game)
            guard !states.isEmpty else {
                self.homeFocus = .hero(.play)
                return
            }
            index = min(index, states.count - 1)

            switch command
            {
            case .up: self.move(&index, by: -1, count: states.count); self.homeFocus = .quickResume(index)
            case .down:
                if index == states.count - 1 { self.homeFocus = .shelf; KeroFeedback.move() }
                else { self.move(&index, by: 1, count: states.count); self.homeFocus = .quickResume(index) }
            case .left: self.homeFocus = .hero(.more); KeroFeedback.move()
            case .back: self.homeFocus = .shelf; KeroFeedback.move()
            case .confirm: self.load(states[index], of: game)
            case .action: self.toggleFavorite(game)
            case .right, .pageUp, .pageDown, .resume: break
            }

        case .dock(let button):
            self.handleDock(command, button: button, hasGames: true)
        }
    }

    private func handleDock(_ command: KeroCommand, button: KeroDockButton, hasGames: Bool)
    {
        let buttons = KeroDockButton.allCases
        var index = buttons.firstIndex(of: button) ?? 0

        switch command
        {
        case .left: self.move(&index, by: -1, count: buttons.count); self.homeFocus = .dock(buttons[index])
        case .right: self.move(&index, by: 1, count: buttons.count); self.homeFocus = .dock(buttons[index])
        case .up, .back:
            if hasGames { self.homeFocus = .shelf; KeroFeedback.move() }
        case .confirm: KeroFeedback.select(); self.perform(button)
        case .down, .action, .pageUp, .pageDown, .resume: break
        }
    }

    // MARK: Library

    private func handleLibrary(_ command: KeroCommand)
    {
        let games = self.libraryGames
        let rail = self.railItems
        let columns = self.libraryIsList ? 1 : max(1, self.libraryColumns)

        if command == .pageUp
        {
            self.showHome()
            return
        }

        switch self.libraryFocus
        {
        case .grid(var index):
            guard !games.isEmpty else {
                self.libraryFocus = .rail(self.selectedRailIndex)
                return
            }
            index = min(index, games.count - 1)

            switch command
            {
            case .left:
                if index % columns == 0 { self.libraryFocus = .rail(self.selectedRailIndex); KeroFeedback.move() }
                else { self.libraryFocus = .grid(index - 1); KeroFeedback.move() }
            case .right:
                if index % columns < columns - 1 && index + 1 < games.count { self.libraryFocus = .grid(index + 1); KeroFeedback.move() }
                else { KeroFeedback.bump() }
            case .up:
                if index - columns >= 0 { self.libraryFocus = .grid(index - columns); KeroFeedback.move() }
                else { KeroFeedback.bump() }
            case .down:
                if index + columns < games.count { self.libraryFocus = .grid(index + columns); KeroFeedback.move() }
                else if index / columns < (games.count - 1) / columns { self.libraryFocus = .grid(games.count - 1); KeroFeedback.move() }
                else { KeroFeedback.bump() }
            case .confirm: KeroFeedback.select(); self.openDetails(games[index])
            case .action: self.toggleFavorite(games[index])
            case .back: self.showHome()
            case .pageUp, .pageDown, .resume: break
            }

        case .rail(var index):
            index = min(index, rail.count - 1)

            switch command
            {
            case .up: self.move(&index, by: -1, count: rail.count); self.libraryFocus = .rail(index)
            case .down: self.move(&index, by: 1, count: rail.count); self.libraryFocus = .rail(index)
            case .right:
                if !games.isEmpty { self.libraryFocus = .grid(0); KeroFeedback.move() }
            case .confirm: KeroFeedback.select(); self.select(rail[index])
            case .back: self.showHome()
            case .left, .action, .pageUp, .pageDown, .resume: break
            }
        }
    }

    private var selectedRailIndex: Int {
        return self.railItems.firstIndex(of: .filter(self.libraryFilter)) ?? 0
    }

    // MARK: Details

    private func handleDetails(_ command: KeroCommand)
    {
        guard let game = self.detailGame else {
            self.closeDetails()
            return
        }

        let topRow: [KeroDetailFocus] = [.play, .loadLatest, .favorite]
        let slotCount = KeroSaveStates.allSlots.count

        switch self.detailFocus
        {
        case .play, .loadLatest, .favorite:
            var index = topRow.firstIndex(of: self.detailFocus) ?? 0
            switch command
            {
            case .left: self.move(&index, by: -1, count: topRow.count); self.detailFocus = topRow[index]
            case .right: self.move(&index, by: 1, count: topRow.count); self.detailFocus = topRow[index]
            case .down: self.detailFocus = .slot(0); KeroFeedback.move()
            case .confirm: KeroFeedback.select(); self.activateDetail(self.detailFocus, game: game)
            case .action: self.toggleFavorite(game)
            case .back: self.closeDetails()
            case .up, .pageUp, .pageDown, .resume: break
            }

        case .slot(var index):
            switch command
            {
            case .left: self.move(&index, by: -1, count: slotCount); self.detailFocus = .slot(index)
            case .right: self.move(&index, by: 1, count: slotCount); self.detailFocus = .slot(index)
            case .up: self.detailFocus = .play; KeroFeedback.move()
            case .confirm: self.activateDetail(self.detailFocus, game: game)
            case .action: self.toggleFavorite(game)
            case .back: self.closeDetails()
            case .down, .pageUp, .pageDown, .resume: break
            }
        }
    }

    func activateDetail(_ focus: KeroDetailFocus, game: KeroGame)
    {
        switch focus
        {
        case .play: self.play(game)
        case .loadLatest:
            if let latest = KeroSaveStates.shared.latest(for: game.identifier) { self.load(latest, of: game) }
            else { KeroFeedback.bump() }
        case .favorite: self.toggleFavorite(game)
        case .slot(let index):
            let slot = KeroSaveStates.allSlots[index]
            if let state = KeroSaveStates.shared.state(for: game.identifier, slot: slot) { self.load(state, of: game) }
            else { KeroFeedback.bump() }
        }
    }

    // MARK: Outer display

    private func handleCompact(_ command: KeroCommand)
    {
        let games = self.compactGames
        let hero = self.compactHeroGame
        let lowest = hero == nil ? 0 : -1

        switch command
        {
        case .up:
            if self.compactFocus > lowest { self.compactFocus -= 1; KeroFeedback.move() } else { KeroFeedback.bump() }
        case .down:
            if self.compactFocus < games.count - 1 { self.compactFocus += 1; KeroFeedback.move() } else { KeroFeedback.bump() }
        case .left, .right, .pageUp, .pageDown:
            let filters = self.compactFilters
            var index = filters.firstIndex(of: self.compactFilter) ?? 0
            self.move(&index, by: (command == .left || command == .pageUp) ? -1 : 1, count: filters.count)
            self.compactFilter = filters[index]
            self.compactFocus = min(max(lowest, self.compactFocus), self.compactGames.count - 1)
            if self.compactFocus < lowest { self.compactFocus = lowest }
        case .confirm:
            KeroFeedback.select()
            if self.compactFocus < 0, let hero { self.play(hero) }
            else if games.indices.contains(self.compactFocus) { self.openDetails(games[self.compactFocus]) }
        case .action:
            if self.compactFocus < 0, let hero { self.toggleFavorite(hero) }
            else if games.indices.contains(self.compactFocus) { self.toggleFavorite(games[self.compactFocus]) }
        case .back, .resume:
            break
        }
    }

    // MARK: Helpers

    private func move(_ index: inout Int, by delta: Int, count: Int)
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
