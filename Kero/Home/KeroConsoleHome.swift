//
//  KeroConsoleHome.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Console-style home: a row of covers, the focused game's art behind everything,
//  its details and actions below, and system buttons at the bottom.
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
                KeroHomeBackdrop(game: self.model.focusedGame)

                VStack(alignment: .leading, spacing: 0) {
                    KeroHomeTopBar(model: self.model)
                        .padding(.horizontal, metrics.margin)
                        .padding(.top, 8)

                    Spacer(minLength: 12)

                    if self.model.games.isEmpty
                    {
                        KeroEmptyLibrary(model: self.model, metrics: metrics)
                            .padding(.horizontal, metrics.margin)
                    }
                    else
                    {
                        KeroGameRow(model: self.model, metrics: metrics)

                        if let game = self.model.focusedGame
                        {
                            KeroGameDetails(model: self.model, game: game)
                                .padding(.horizontal, metrics.margin)
                                .padding(.top, metrics.cardSize * 0.14)
                                .id(game.identifier)
                                .transition(.opacity)
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(alignment: .bottom) {
                        KeroSystemRow(model: self.model)
                        Spacer()
                        KeroControllerHints(model: self.model)
                    }
                    .padding(.horizontal, metrics.margin)
                    .padding(.bottom, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Layout -

struct KeroHomeMetrics
{
    var cardSize: CGFloat
    var spacing: CGFloat
    var margin: CGFloat

    init(size: CGSize)
    {
        // Big enough to read box art, small enough to show neighbours on either side.
        let fromHeight = size.height * 0.30
        let fromWidth = size.width * 0.34
        self.cardSize = min(230, max(112, min(fromHeight, fromWidth)))
        self.spacing = self.cardSize * 0.11
        self.margin = size.width > 600 ? 40 : 20
    }
}

// MARK: - Backdrop -

/// The focused game's art, blurred and darkened, fills the screen behind everything.
private struct KeroHomeBackdrop: View
{
    var game: KeroGame?

    var body: some View
    {
        ZStack {
            KeroTheme.background

            if let game
            {
                Group {
                    if game.artworkURL != nil
                    {
                        KeroGameCover(game: game, cornerRadius: 0)
                            .blur(radius: 50)
                            .opacity(0.55)
                    }
                    else
                    {
                        RadialGradient(colors: [KeroTheme.tint(for: game.system).opacity(0.55), .clear],
                                       center: .topTrailing, startRadius: 0, endRadius: 900)
                    }
                }
                .id(game.identifier)
                .transition(.opacity.animation(.easeInOut(duration: 0.45)))
            }

            // Keep text readable: darker toward the bottom and left.
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: self.game?.identifier)
    }
}

// MARK: - Top Bar -

private struct KeroHomeTopBar: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        HStack(spacing: 14) {
            Text("Kero")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(KeroTheme.primaryText)

            if let nowPlaying = self.model.nowPlayingGame
            {
                Button {
                    self.model.host?.resumeNowPlaying()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(nowPlaying.name)
                            .lineLimit(1)
                    }
                    .font(KeroTheme.body(13, .medium))
                    .foregroundStyle(KeroTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(KeroTheme.surfaceHighlight, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Resume \(nowPlaying.name)"))
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                if self.model.isControllerConnected
                {
                    Image(systemName: "gamecontroller.fill")
                }

                TimelineView(.everyMinute) { context in
                    HStack(spacing: 14) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .monospacedDigit()
                        KeroBatteryIndicator()
                    }
                }
            }
            .font(KeroTheme.body(14, .medium))
            .foregroundStyle(KeroTheme.secondaryText)
            .lineLimit(1)
            .fixedSize()
        }
        .frame(height: 36)
    }
}

private struct KeroBatteryIndicator: View
{
    var body: some View
    {
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState

        if level >= 0
        {
            HStack(spacing: 4) {
                Text("\(Int((level * 100).rounded()))%")
                    .monospacedDigit()
                Image(systemName: self.symbolName(level: level, charging: state == .charging || state == .full))
            }
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

// MARK: - Game Row -

private struct KeroGameRow: View
{
    @ObservedObject var model: KeroHomeModel
    let metrics: KeroHomeMetrics

    var body: some View
    {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: self.metrics.spacing) {
                    ForEach(Array(self.model.games.enumerated()), id: \.element.identifier) { index, game in
                        KeroGameCard(game: game,
                                     size: self.metrics.cardSize,
                                     isFocused: index == self.model.focusedGameIndex,
                                     isRowFocused: self.model.row == .games,
                                     isRunning: self.model.isRunning(game))
                            .id(game.identifier)
                            .onTapGesture { self.model.tapGame(at: index) }
                            .contextMenu {
                                Button { self.model.perform(.play, for: game) } label: {
                                    Label(self.model.isRunning(game) ? "Resume" : "Play", systemImage: "play.fill")
                                }
                                Button { self.model.perform(.favorite, for: game) } label: {
                                    Label(game.isFavorite ? "Remove Favorite" : "Favorite", systemImage: game.isFavorite ? "star.slash" : "star")
                                }
                                Button(role: .destructive) { self.model.perform(.delete, for: game) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, self.metrics.margin)
                // Room for the focused card's scale and outline.
                .padding(.vertical, self.metrics.cardSize * 0.1)
            }
            .frame(height: self.metrics.cardSize * 1.2)
            .onChange(of: self.model.focusedGameIndex) { _, index in
                guard self.model.games.indices.contains(index) else { return }
                withAnimation(KeroTheme.focusSpring) {
                    proxy.scrollTo(self.model.games[index].identifier, anchor: UnitPoint(x: 0.3, y: 0.5))
                }
            }
        }
    }
}

private struct KeroGameCard: View
{
    let game: KeroGame
    let size: CGFloat
    let isFocused: Bool
    let isRowFocused: Bool
    let isRunning: Bool

    var body: some View
    {
        KeroGameCover(game: self.game, cornerRadius: self.size * 0.08)
            .frame(width: self.size, height: self.size)
            .overlay(alignment: .topTrailing) {
                if self.game.isFavorite
                {
                    Image(systemName: "star.fill")
                        .font(.system(size: max(10, self.size * 0.08), weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(self.size * 0.06)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if self.isRunning
                {
                    Label("Playing", systemImage: "play.fill")
                        .font(.system(size: max(9, self.size * 0.065), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(self.size * 0.05)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: self.size * 0.08 + 5, style: .continuous)
                    .stroke(KeroTheme.focus, lineWidth: 3)
                    .padding(-5)
                    .opacity(self.isFocused && self.isRowFocused ? 1 : 0)
            )
            .shadow(color: .black.opacity(self.isFocused ? 0.55 : 0.3), radius: self.isFocused ? 18 : 8, y: self.isFocused ? 10 : 4)
            .scaleEffect(self.isFocused ? 1.0 : 0.84)
            .opacity(self.isFocused ? 1 : 0.7)
            .animation(KeroTheme.focusSpring, value: self.isFocused)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(self.game.name), \(self.game.system.name)"))
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Details -

private struct KeroGameDetails: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame

    var body: some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.game.name)
                .font(KeroTheme.title(26))
                .foregroundStyle(KeroTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(self.subtitle)
                .font(KeroTheme.body(14))
                .foregroundStyle(KeroTheme.secondaryText)

            HStack(spacing: 12) {
                ForEach(Array(self.model.actions(for: self.game).enumerated()), id: \.element) { index, action in
                    KeroActionButton(action: action,
                                     game: self.game,
                                     isRunning: self.model.isRunning(self.game),
                                     isFocused: self.model.showsFocus && self.model.row == .actions && self.model.actionIndex == index) {
                        KeroFeedback.select()
                        self.model.perform(action, for: self.game)
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        var parts = [self.game.system.name]

        if let playedDate = self.game.playedDate
        {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Played " + formatter.localizedString(for: playedDate, relativeTo: Date()))
        }
        else
        {
            parts.append("Never played")
        }

        return parts.joined(separator: "  ·  ")
    }
}

private struct KeroActionButton: View
{
    let action: KeroGameAction
    let game: KeroGame
    let isRunning: Bool
    let isFocused: Bool
    let perform: () -> Void

    var body: some View
    {
        Button(action: self.perform) {
            Group {
                switch self.action
                {
                case .play:
                    Label(self.isRunning ? "Resume" : "Play", systemImage: "play.fill")
                        .font(KeroTheme.body(16, .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 26)
                        .frame(height: 44)
                        .background(Color.white, in: Capsule())

                case .restart:
                    self.circle("arrow.counterclockwise")

                case .favorite:
                    self.circle(self.game.isFavorite ? "star.fill" : "star", tint: self.game.isFavorite ? .yellow : .white)

                case .delete:
                    self.circle("trash")
                }
            }
            .overlay(
                Capsule()
                    .stroke(KeroTheme.accent, lineWidth: 3)
                    .padding(-5)
                    .opacity(self.isFocused ? 1 : 0)
            )
            .scaleEffect(self.isFocused ? 1.05 : 1)
            .animation(KeroTheme.focusSpring, value: self.isFocused)
        }
        .buttonStyle(KeroPressStyle())
        .accessibilityLabel(Text(self.accessibilityText))
    }

    private func circle(_ symbol: String, tint: Color = .white) -> some View
    {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(KeroTheme.surfaceHighlight, in: Circle())
    }

    private var accessibilityText: String {
        switch self.action
        {
        case .play: return self.isRunning ? "Resume" : "Play"
        case .restart: return "Restart"
        case .favorite: return self.game.isFavorite ? "Remove Favorite" : "Favorite"
        case .delete: return "Delete"
        }
    }
}

struct KeroPressStyle: ButtonStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Empty State -

private struct KeroEmptyLibrary: View
{
    @ObservedObject var model: KeroHomeModel
    let metrics: KeroHomeMetrics

    var body: some View
    {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                self.model.perform(.importGames)
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: self.metrics.cardSize * 0.2, weight: .light))
                    Text("Add Games")
                        .font(KeroTheme.body(15, .semibold))
                }
                .foregroundStyle(KeroTheme.primaryText)
                .frame(width: self.metrics.cardSize, height: self.metrics.cardSize)
                .background(KeroTheme.surface, in: RoundedRectangle(cornerRadius: self.metrics.cardSize * 0.08, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: self.metrics.cardSize * 0.08, style: .continuous)
                        .strokeBorder(KeroTheme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
            }
            .buttonStyle(KeroPressStyle())

            Text("Your library is empty")
                .font(KeroTheme.title(24))
                .foregroundStyle(KeroTheme.primaryText)
                .padding(.top, 8)

            Text("Import game files you own (.gba, .gbc, .gb) from Files or iCloud Drive.")
                .font(KeroTheme.body(14))
                .foregroundStyle(KeroTheme.secondaryText)
        }
    }
}

// MARK: - System Row -

private struct KeroSystemRow: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        HStack(spacing: 18) {
            ForEach(Array(KeroSystemButton.allCases.enumerated()), id: \.element) { index, button in
                let isFocused = self.model.showsFocus && self.model.row == .system && self.model.systemIndex == index

                Button {
                    KeroFeedback.select()
                    self.model.perform(button)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: button.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(KeroTheme.primaryText)
                            .frame(width: 50, height: 50)
                            .background(KeroTheme.surfaceHighlight, in: Circle())
                            .overlay(Circle().stroke(KeroTheme.accent, lineWidth: 3).padding(-4).opacity(isFocused ? 1 : 0))

                        Text(button.title)
                            .font(KeroTheme.body(11, .medium))
                            .foregroundStyle(isFocused ? KeroTheme.primaryText : KeroTheme.tertiaryText)
                    }
                }
                .buttonStyle(KeroPressStyle())
                .animation(KeroTheme.focusSpring, value: isFocused)
            }
        }
    }
}

// MARK: - Hints -

private struct KeroControllerHints: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        if self.model.isControllerConnected
        {
            HStack(spacing: 16) {
                self.hint("A", self.model.row == .games ? "Play" : "Select")
                self.hint("Y", "Favorite")
                if self.model.row != .games { self.hint("B", "Back") }
            }
            .padding(.bottom, 14)
            .transition(.opacity)
        }
    }

    private func hint(_ button: String, _ title: String) -> some View
    {
        HStack(spacing: 6) {
            Text(button)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.85), in: Circle())
            Text(title)
                .font(KeroTheme.body(13, .medium))
                .foregroundStyle(KeroTheme.secondaryText)
        }
    }
}
