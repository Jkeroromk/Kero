//
//  KeroConsoleHome.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Home on the big (inner) display: the focused game up top with its stats, actions and quick
//  resume slots, the "Jump back in" shelf below, and the dock at the bottom.
//

import SwiftUI
import UIKit

import KeroEngine

struct KeroConsoleHome: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        GeometryReader { geometry in
            let metrics = KeroHomeMetrics(size: geometry.size)

            ZStack {
                KeroHomeBackdrop(game: self.model.focusedGame,
                                 center: UnitPoint(x: 0.22, y: 0.18),
                                 radius: CGSize(width: 900 * metrics.scale, height: 520 * metrics.scale),
                                 fade: 0.7)

                VStack(alignment: .leading, spacing: 22 * metrics.scale) {
                    KeroHomeTopBar(model: self.model, selected: .home)

                    if let game = self.model.focusedGame
                    {
                        KeroHomeHero(model: self.model, game: game, metrics: metrics)
                        KeroHomeShelf(model: self.model, metrics: metrics)
                    }
                    else
                    {
                        KeroEmptyHome(model: self.model, metrics: metrics)
                    }

                    Spacer(minLength: 0)

                    HStack(alignment: .center) {
                        KeroHomeDock(model: self.model, metrics: metrics)
                        Spacer(minLength: 12)
                        KeroHomeHints(model: self.model)
                    }
                }
                .padding(.top, 26 * metrics.scale)
                .padding(.horizontal, 40 * metrics.scale)
                .padding(.bottom, 24 * metrics.scale)
            }
        }
    }
}

// MARK: - Layout -

/// The design is drawn for the iPhone Duo's inner display (1180 × 830 pt); other sizes scale it.
struct KeroHomeMetrics
{
    var size: CGSize
    var scale: CGFloat

    init(size: CGSize)
    {
        self.size = size
        self.scale = min(1.25, max(0.5, min(size.width / 1180, size.height / 830)))
    }

    func s(_ value: CGFloat) -> CGFloat { value * self.scale }
    /// Font sizes shrink less than the layout, so text stays readable on small screens.
    func font(_ value: CGFloat) -> CGFloat { max(value * 0.72, value * self.scale) }
}

// MARK: - Backdrop -

/// The ground colour with a soft glow taken from the game's cover (or its system), like light from the screen.
struct KeroHomeBackdrop: View
{
    var game: KeroGame?
    var center: UnitPoint
    var radius: CGSize
    var fade: CGFloat
    var intensity: Double = 1
    var darkensBottom = true

    var body: some View
    {
        ZStack {
            KeroTheme.background

            if let game = self.game
            {
                KeroGameGlow(game: game, center: self.center, radius: self.radius, fade: self.fade)
                    .opacity(self.intensity)
                    .id(game.identifier)
                    .transition(.opacity)
            }

            if self.darkensBottom
            {
                LinearGradient(stops: [.init(color: KeroTheme.background.opacity(0), location: 0.4),
                                       .init(color: KeroTheme.background.opacity(0.85), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: self.game?.identifier)
        .allowsHitTesting(false)
    }
}

private struct KeroGameGlow: View
{
    let game: KeroGame
    var center: UnitPoint
    var radius: CGSize
    var fade: CGFloat

    @State private var coverColor: UIColor?

    private var color: Color {
        if self.game.artworkURL != nil, let coverColor = self.coverColor
        {
            // Covers vary a lot in brightness: keep the hue, settle on a deep glow.
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            coverColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            return Color(hue: Double(hue), saturation: Double(min(0.75, saturation * 1.1)), brightness: Double(min(0.45, max(0.25, brightness * 0.6))))
        }
        if self.game.artworkURL != nil
        {
            return KeroTheme.tint(for: self.game.system)
        }
        return KeroCoverPalette.colors(system: self.game.system, seed: self.game.identifier).top.darker(0.12)
    }

    var body: some View
    {
        GeometryReader { geometry in
            let radiusX = max(1, self.radius.width)
            RadialGradient(colors: [self.color, self.color.opacity(0)], center: .center, startRadius: 0, endRadius: radiusX * self.fade)
                .frame(width: radiusX * 2, height: radiusX * 2)
                .scaleEffect(x: 1, y: self.radius.height / radiusX)
                .position(x: geometry.size.width * self.center.x, y: geometry.size.height * self.center.y)
        }
        .task(id: self.game.artworkURL) {
            guard let url = self.game.artworkURL else {
                self.coverColor = nil
                return
            }
            self.coverColor = KeroArtworkCache.shared.cachedAverageColor(for: url)
            if self.coverColor == nil
            {
                let color = await KeroArtworkCache.shared.averageColor(for: url)
                withAnimation(.easeInOut(duration: 0.3)) { self.coverColor = color }
            }
        }
    }
}

// MARK: - Top Bar -

struct KeroHomeTopBar: View
{
    @ObservedObject var model: KeroHomeModel
    var selected: KeroHomeSection

    var body: some View
    {
        ZStack {
            HStack {
                KeroWordmark()
                Spacer(minLength: 12)
                KeroStatusItems(isControllerConnected: self.model.isControllerConnected)
            }

            KeroSectionSwitch(selected: self.selected) { section in
                if section == .home { self.model.showHome() } else { self.model.showLibrary() }
            }
        }
        .frame(height: 40)
    }
}

/// Home / Library.
struct KeroSectionSwitch: View
{
    var selected: KeroHomeSection
    var choose: (KeroHomeSection) -> Void

    var body: some View
    {
        HStack(spacing: 4) {
            self.item("Home", .home)
            self.item("Library", .library)
        }
        .padding(4)
        .background(KeroTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(KeroTheme.stroke, lineWidth: 1))
    }

    private func item(_ title: String, _ section: KeroHomeSection) -> some View
    {
        let isSelected = self.selected == section

        return Button {
            guard !isSelected else { return }
            KeroFeedback.tap()
            self.choose(section)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? KeroTheme.background : Color(hex: 0xC9CCD3))
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(isSelected ? KeroTheme.primaryText : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Controller, clock and battery.
struct KeroStatusItems: View
{
    var isControllerConnected: Bool
    var fontSize: CGFloat = 13

    var body: some View
    {
        HStack(spacing: 16) {
            if self.isControllerConnected
            {
                Image(systemName: "gamecontroller")
                    .font(.system(size: self.fontSize * 1.3, weight: .regular))
                    .accessibilityLabel("Controller connected")
            }

            TimelineView(.everyMinute) { context in
                HStack(spacing: 16) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .monospacedDigit()
                    KeroBatteryIndicator()
                }
            }
        }
        .font(.system(size: self.fontSize, weight: .medium))
        .foregroundStyle(KeroTheme.statusText)
        .lineLimit(1)
        .fixedSize()
    }
}

struct KeroBatteryIndicator: View
{
    var body: some View
    {
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState

        if level >= 0
        {
            HStack(spacing: 6) {
                Text("\(Int((level * 100).rounded()))%")
                    .monospacedDigit()
                Image(systemName: self.symbolName(level: level, charging: state == .charging || state == .full))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Battery \(Int((level * 100).rounded())) percent"))
        }
    }

    private func symbolName(level: Float, charging: Bool) -> String
    {
        if charging { return "battery.100.bolt" }

        switch level
        {
        case 0.88...: return "battery.100"
        case 0.63...: return "battery.75"
        case 0.38...: return "battery.50"
        case 0.13...: return "battery.25"
        default: return "battery.0"
        }
    }
}

// MARK: - Hero -

private struct KeroHomeHero: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    let metrics: KeroHomeMetrics

    var body: some View
    {
        let isRunning = self.model.isRunning(self.game)
        let showsQuickResume = self.metrics.size.width >= 700

        HStack(alignment: .bottom, spacing: self.metrics.s(36)) {
            Button {
                self.model.openDetails(self.game)
            } label: {
                KeroGameCover(game: self.game, cornerRadius: self.metrics.s(22), labelsArtwork: true)
                    .frame(width: self.metrics.s(300), height: self.metrics.s(300))
                    .shadow(color: .black.opacity(0.55), radius: self.metrics.s(30), y: self.metrics.s(30))
                    .overlay(RoundedRectangle(cornerRadius: self.metrics.s(22), style: .continuous).strokeBorder(KeroTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel(Text("\(self.game.name), game details"))
            .contextMenu { KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true) }

            VStack(alignment: .leading, spacing: self.metrics.s(16)) {
                HStack(spacing: 8) {
                    KeroStatusPill(game: self.game, isPaused: isRunning)
                    Text(KeroGameText.systemLine(self.game))
                        .font(.system(size: self.metrics.font(13)))
                        .foregroundStyle(KeroTheme.statusText)
                        .lineLimit(1)
                }

                Text(self.game.name)
                    .font(.system(size: self.metrics.font(48), weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(KeroTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)

                HStack(spacing: 10) {
                    KeroStatTile(value: KeroFormat.playTime(self.game.playSeconds), label: "Played", metrics: self.metrics)
                    KeroStatTile(value: self.game.playedDate.map { KeroFormat.when($0) } ?? "Never", label: "Last played", metrics: self.metrics)
                    KeroStatTile(value: "\(KeroSaveStates.shared.states(for: self.game.identifier).count)", label: "Save states", metrics: self.metrics)
                }

                self.actions(isRunning: isRunning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)

            if showsQuickResume
            {
                KeroQuickResume(model: self.model, game: self.game, metrics: self.metrics)
                    .frame(width: self.metrics.s(236))
            }
        }
        .id(self.game.identifier)
        .transition(.opacity)
    }

    private func actions(isRunning: Bool) -> some View
    {
        let size = self.metrics.s(52)

        return HStack(spacing: 10) {
            Button {
                KeroFeedback.select()
                self.model.play(self.game)
            } label: {
                KeroPrimaryPill(title: isRunning ? "Resume" : "Play", height: size, fontSize: self.metrics.font(17))
                    .keroFocusRing(self.isFocused(.play), shape: Capsule())
            }
            .buttonStyle(KeroPressStyle())

            if isRunning
            {
                Button {
                    KeroFeedback.select()
                    self.model.restart(self.game)
                } label: {
                    KeroCircleIcon(symbol: "arrow.counterclockwise", size: size)
                        .keroFocusRing(self.isFocused(.restart), shape: Circle())
                }
                .buttonStyle(KeroPressStyle())
                .accessibilityLabel("Restart")
            }

            Button {
                self.model.toggleFavorite(self.game)
            } label: {
                KeroCircleIcon(symbol: self.game.isFavorite ? "star.fill" : "star", size: size,
                               tint: self.game.isFavorite ? KeroTheme.favorite : KeroTheme.primaryText)
                    .keroFocusRing(self.isFocused(.favorite), shape: Circle())
            }
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel(self.game.isFavorite ? "Remove from Favorites" : "Add to Favorites")

            Menu {
                KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true, includesPlay: false)
            } label: {
                KeroCircleIcon(symbol: "ellipsis", size: size)
                    .keroFocusRing(self.isFocused(.more), shape: Circle())
            }
            .menuStyle(.button)
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel("More options")
        }
    }

    private func isFocused(_ action: KeroHeroAction) -> Bool
    {
        return self.model.showsFocus && self.model.section == .home && self.model.homeFocus == .hero(action)
    }
}

/// "Paused" while the game is suspended, otherwise when it was last played.
struct KeroStatusPill: View
{
    let game: KeroGame
    var isPaused: Bool
    var fontSize: CGFloat = 12

    var body: some View
    {
        if self.isPaused
        {
            KeroChip(text: "Paused", foreground: KeroTheme.background, background: KeroTheme.powerLED, fontSize: self.fontSize)
        }
        else if let played = self.game.playedDate
        {
            KeroChip(text: "Played " + KeroFormat.when(played).lowercasedFirst, foreground: KeroTheme.primaryText,
                     background: Color.white.opacity(0.1), fontSize: self.fontSize)
        }
        else
        {
            KeroChip(text: "New", foreground: KeroTheme.background, background: KeroTheme.link, fontSize: self.fontSize)
        }
    }
}

private struct KeroStatTile: View
{
    var value: String
    var label: String
    let metrics: KeroHomeMetrics

    var body: some View
    {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.value)
                .font(.system(size: self.metrics.font(18), weight: .bold))
                .foregroundStyle(KeroTheme.primaryText)
                .lineLimit(1)
                .monospacedDigit()
            Text(self.label)
                .font(.system(size: self.metrics.font(12)))
                .foregroundStyle(KeroTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, self.metrics.s(10))
        .padding(.horizontal, self.metrics.s(14))
        .keroCard(cornerRadius: 14, fill: KeroTheme.surface)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quick Resume -

private struct KeroQuickResume: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    let metrics: KeroHomeMetrics

    var body: some View
    {
        let states = self.model.quickResumeStates(for: self.game)

        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK RESUME")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(KeroTheme.secondaryText)

            if states.isEmpty
            {
                Text("Save states from the pause menu show up here, ready to jump straight back in.")
                    .font(.system(size: 12))
                    .foregroundStyle(KeroTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .keroCard(cornerRadius: 14, fill: Color.white.opacity(0.03))
            }

            ForEach(Array(states.enumerated()), id: \.element.id) { index, state in
                Button {
                    self.model.load(state, of: self.game)
                } label: {
                    HStack(spacing: 12) {
                        KeroSaveStateThumbnail(state: state, system: self.game.system, cornerRadius: 8)
                            .frame(width: self.metrics.s(72), height: self.metrics.s(48))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(KeroTheme.primaryText)
                            Text(state.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(KeroTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .keroCard(cornerRadius: 14)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .keroFocusRing(self.model.showsFocus && self.model.homeFocus == .quickResume(index),
                                   shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(KeroPressStyle())
                .accessibilityLabel(Text("Load \(state.name), \(state.detail)"))
            }
        }
    }
}

// MARK: - Shelf -

private struct KeroHomeShelf: View
{
    @ObservedObject var model: KeroHomeModel
    let metrics: KeroHomeMetrics

    var body: some View
    {
        let shelf = self.model.shelfGames
        let size = self.metrics.s(132)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.first?.playedDate == nil ? "Your games" : "Jump back in")
                    .font(.system(size: self.metrics.font(15), weight: .semibold))
                    .foregroundStyle(KeroTheme.primaryText)
                Spacer()
                Button {
                    self.model.showLibrary()
                } label: {
                    Text(self.model.games.count == 1 ? "All 1 game" : "All \(self.model.games.count) games")
                        .font(.system(size: 13))
                        .foregroundStyle(KeroTheme.link)
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: self.metrics.s(16)) {
                        ForEach(Array(shelf.enumerated()), id: \.element.identifier) { index, game in
                            KeroShelfItem(model: self.model, game: game, index: index, size: size)
                                .id(game.identifier)
                        }
                    }
                    // Room for the focus ring.
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .padding(-8)
                .onChange(of: self.model.focusedGameIndex) { _, index in
                    guard shelf.indices.contains(index) else { return }
                    withAnimation(KeroTheme.focusSpring) {
                        proxy.scrollTo(shelf[index].identifier, anchor: UnitPoint(x: 0.3, y: 0.5))
                    }
                }
            }
        }
    }
}

private struct KeroShelfItem: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    let index: Int
    let size: CGFloat

    var body: some View
    {
        let isSelected = index == self.model.focusedGameIndex
        let isFocused = isSelected && self.model.showsFocus && self.model.homeFocus == .shelf

        VStack(alignment: .leading, spacing: 8) {
            KeroGameCover(game: self.game, cornerRadius: 16, labelsArtwork: true)
                .frame(width: self.size, height: self.size)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(KeroTheme.stroke, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if self.game.isFavorite
                    {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KeroTheme.favorite)
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }
                .keroFocusRing(isFocused, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(self.whenText)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? KeroTheme.primaryText : KeroTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: self.size, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { self.model.tapShelfGame(at: self.index) }
        .contextMenu { KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(self.game.name), \(self.game.system.name), \(self.whenText)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelected ? Text("Plays the game") : Text("Shows the game above"))
    }

    private var whenText: String {
        if self.model.isRunning(self.game) { return "Paused" }
        return self.game.playedDate.map { KeroFormat.when($0) } ?? "Not played yet"
    }
}

// MARK: - Empty -

private struct KeroEmptyHome: View
{
    @ObservedObject var model: KeroHomeModel
    let metrics: KeroHomeMetrics

    var body: some View
    {
        HStack(alignment: .center, spacing: self.metrics.s(36)) {
            Button {
                self.model.host?.showImport()
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: self.metrics.s(64), weight: .light))
                    Text("Add Games")
                        .font(.system(size: self.metrics.font(17), weight: .semibold))
                }
                .foregroundStyle(KeroTheme.primaryText)
                .frame(width: self.metrics.s(300), height: self.metrics.s(300))
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: self.metrics.s(22), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: self.metrics.s(22), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                )
                .contentShape(RoundedRectangle(cornerRadius: self.metrics.s(22), style: .continuous))
            }
            .buttonStyle(KeroPressStyle())

            VStack(alignment: .leading, spacing: self.metrics.s(16)) {
                Text("Your library is empty")
                    .font(.system(size: self.metrics.font(48), weight: .heavy))
                    .foregroundStyle(KeroTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                Text("Add game files you own (.nds, .gba, .gbc, .gb or .zip) from Files, a folder, AirDrop, or a computer's browser with Wi-Fi Transfer.")
                    .font(.system(size: self.metrics.font(15)))
                    .foregroundStyle(KeroTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)

                HStack(spacing: 10) {
                    Button {
                        KeroFeedback.select()
                        self.model.host?.showImport()
                    } label: {
                        KeroPrimaryPill(title: "Add Games", symbol: "plus", height: self.metrics.s(52), fontSize: self.metrics.font(17))
                    }
                    .buttonStyle(KeroPressStyle())

                    Button {
                        self.model.host?.showWiFiTransfer()
                    } label: {
                        KeroGlassPill(title: "Wi-Fi Transfer", symbol: "wifi", height: self.metrics.s(52), fontSize: self.metrics.font(15), horizontalPadding: 20)
                    }
                    .buttonStyle(KeroPressStyle())
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, self.metrics.s(20))
    }
}

// MARK: - Dock -

private struct KeroHomeDock: View
{
    @ObservedObject var model: KeroHomeModel
    let metrics: KeroHomeMetrics

    var body: some View
    {
        let height = max(38, self.metrics.s(44))

        HStack(spacing: 10) {
            ForEach(KeroDockButton.allCases) { button in
                let isFocused = self.model.showsFocus && self.model.section == .home && self.model.homeFocus == .dock(button)

                Button {
                    KeroFeedback.select()
                    self.model.perform(button)
                } label: {
                    if button == .settings
                    {
                        KeroCircleIcon(symbol: button.symbol, size: height)
                            .keroFocusRing(isFocused, shape: Circle())
                    }
                    else
                    {
                        KeroGlassPill(title: button.title, symbol: button.symbol, height: height, fontSize: 14)
                            .keroFocusRing(isFocused, shape: Capsule())
                    }
                }
                .buttonStyle(KeroPressStyle())
                .accessibilityLabel(button.title)
            }
        }
    }
}

// MARK: - Hints -

private struct KeroHomeHints: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        if self.model.isControllerConnected
        {
            HStack(spacing: 18) {
                KeroButtonHint(button: "A", title: self.confirmTitle)
                if self.model.focusedGame != nil
                {
                    KeroButtonHint(button: "X", title: "Favorite")
                }
                if self.model.homeFocus != .shelf && self.model.focusedGame != nil
                {
                    KeroButtonHint(button: "B", title: "Back")
                }
                if self.model.nowPlayingGame != nil
                {
                    KeroButtonHint(button: "≡", title: "Resume")
                }
            }
            .transition(.opacity)
        }
    }

    private var confirmTitle: String {
        switch self.model.homeFocus
        {
        case .shelf:
            guard let game = self.model.focusedGame else { return "Select" }
            return self.model.isRunning(game) ? "Resume" : "Play"
        case .quickResume: return "Load"
        case .hero, .dock: return "Select"
        }
    }
}

// MARK: - Shared -

/// Play, favourite, details, rename, cover and delete: the long-press menu on a game, and the hero's "…".
struct KeroGameMenuItems: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    var includesDetails = false
    var includesPlay = true

    var body: some View
    {
        if self.includesPlay
        {
            Button { self.model.play(self.game) } label: {
                Label(self.model.isRunning(self.game) ? "Resume" : "Play", systemImage: "play.fill")
            }
            Button { self.model.toggleFavorite(self.game) } label: {
                Label(self.game.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: self.game.isFavorite ? "star.slash" : "star")
            }
        }
        if self.includesDetails
        {
            Button { self.model.openDetails(self.game) } label: {
                Label("Game Details", systemImage: "info.circle")
            }
        }
        Button { self.model.host?.rename(self.game) } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { self.model.host?.chooseCover(for: self.game) } label: {
            Label("Choose Cover", systemImage: "photo")
        }
        if self.game.artworkFileName != nil
        {
            Button { self.model.host?.removeCover(of: self.game) } label: {
                Label("Remove Cover", systemImage: "photo.badge.minus")
            }
        }
        Divider()
        Button(role: .destructive) { self.model.host?.confirmDelete(self.game) } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

enum KeroGameText
{
    /// "Game Boy Advance · USA · English"
    static func systemLine(_ game: KeroGame, short: Bool = false) -> String
    {
        var parts = [short ? game.system.shortName : game.system.name]
        if let region = game.region, !region.isEmpty { parts.append(region) }
        if game.isChineseTranslation { parts.append("Chinese fan translation") }
        else if let languages = KeroFormat.languages(game.languages) { parts.append(languages) }
        return parts.joined(separator: " · ")
    }
}

extension String
{
    /// "Yesterday" → "yesterday", for "Played yesterday". Month names ("Oct 28") stay as they are.
    var lowercasedFirst: String {
        guard let first = self.first, first.isUppercase else { return self }
        if let firstWord = self.split(separator: " ").first, Calendar.current.shortMonthSymbols.contains(String(firstWord)) { return self }
        return first.lowercased() + self.dropFirst()
    }
}
