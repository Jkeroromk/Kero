//
//  KeroCompactHome.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Home on a narrow window: the iPhone Duo's outer display when Settings › When Folded is Keep
//  Playing (or any iPhone held upright). The paused or last-played game on a card, system
//  filters, and a list of the rest.
//

import SwiftUI

import KeroEngine

struct KeroCompactHome: View
{
    @ObservedObject var model: KeroHomeModel

    var body: some View
    {
        ZStack {
            KeroHomeBackdrop(game: self.model.compactHeroGame ?? self.model.games.first,
                             center: UnitPoint(x: 0.5, y: 0.1),
                             radius: CGSize(width: 420, height: 320),
                             fade: 0.72, darkensBottom: false)

            VStack(alignment: .leading, spacing: 16) {
                self.header

                if self.model.games.isEmpty
                {
                    self.emptyState
                    Spacer(minLength: 0)
                }
                else
                {
                    if let hero = self.model.compactHeroGame
                    {
                        KeroCompactHero(model: self.model, game: hero, isFocused: self.model.showsFocus && self.model.compactFocus == -1)
                    }

                    if self.model.compactFilters.count > 2
                    {
                        self.filters
                    }

                    self.list
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
        }
    }

    private var header: some View
    {
        HStack {
            KeroWordmark(size: 13, ledSize: 7)
            Spacer()
            HStack(spacing: 8) {
                Button {
                    self.model.host?.showImport()
                } label: {
                    KeroCircleIcon(symbol: "plus", size: 36)
                }
                .buttonStyle(KeroPressStyle())
                .accessibilityLabel("Add Games")

                Button {
                    self.model.host?.showSettings()
                } label: {
                    KeroCircleIcon(symbol: "gearshape", size: 36)
                }
                .buttonStyle(KeroPressStyle())
                .accessibilityLabel("Settings")
            }
        }
        .frame(height: 36)
    }

    private var filters: some View
    {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(self.model.compactFilters, id: \.self) { filter in
                    let isSelected = filter == self.model.compactFilter

                    Button {
                        KeroFeedback.tap()
                        withAnimation(.easeInOut(duration: 0.2)) { self.model.compactFilter = filter }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? KeroTheme.background : KeroTheme.mutedText)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(isSelected ? KeroTheme.primaryText : Color.white.opacity(0.05), in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var list: some View
    {
        let games = self.model.compactGames

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(games.enumerated()), id: \.element.identifier) { index, game in
                        KeroCompactRow(model: self.model, game: game, isFocused: self.model.showsFocus && self.model.compactFocus == index)
                            .id(game.identifier)
                    }

                    if games.isEmpty
                    {
                        Text(self.model.compactFilter == .all ? "That's every game." : "No other \(self.model.compactFilter.title) games.")
                            .font(.system(size: 13))
                            .foregroundStyle(KeroTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .onChange(of: self.model.compactFocus) { _, index in
                guard games.indices.contains(index) else { return }
                withAnimation(KeroTheme.focusSpring) { proxy.scrollTo(games[index].identifier, anchor: .center) }
            }
        }
    }

    private var emptyState: some View
    {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your library is empty")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(KeroTheme.primaryText)
            Text("Add game files you own (.nds, .gba, .gbc, .gb or .zip) from Files, AirDrop or Wi-Fi Transfer.")
                .font(.system(size: 14))
                .foregroundStyle(KeroTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    self.model.host?.showImport()
                } label: {
                    KeroPrimaryPill(title: "Add Games", symbol: "plus", height: 44, fontSize: 15, horizontalPadding: 20)
                }
                .buttonStyle(KeroPressStyle())

                Button {
                    self.model.host?.showWiFiTransfer()
                } label: {
                    KeroGlassPill(title: "Wi-Fi Transfer", symbol: "wifi", height: 44, fontSize: 14)
                }
                .buttonStyle(KeroPressStyle())
            }
        }
        .padding(18)
        .keroCard(cornerRadius: 22, fill: KeroTheme.surface)
    }
}

private struct KeroCompactHero: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    var isFocused: Bool

    var body: some View
    {
        let isPaused = self.model.isRunning(self.game)

        HStack(spacing: 16) {
            Button {
                self.model.openDetails(self.game)
            } label: {
                KeroGameCover(game: self.game, cornerRadius: 16, showsTitle: false)
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.5), radius: 15, y: 14)
            }
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel(Text("\(self.game.name), game details"))

            VStack(alignment: .leading, spacing: 6) {
                Text((isPaused ? "PAUSED · " : "LAST PLAYED · ") + self.game.system.shortName)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(isPaused ? KeroTheme.powerLED : KeroTheme.secondaryText)
                Text(self.game.name)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(KeroTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(self.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(KeroTheme.secondaryText)
                    .lineLimit(1)

                Button {
                    KeroFeedback.select()
                    self.model.play(self.game)
                } label: {
                    KeroPrimaryPill(title: isPaused ? "Resume" : "Play", height: 40, fontSize: 14, horizontalPadding: 18)
                        .keroFocusRing(self.isFocused, shape: Capsule())
                }
                .buttonStyle(KeroPressStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .keroCard(cornerRadius: 22, fill: KeroTheme.surface)
        .contextMenu { KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true) }
    }

    private var detail: String {
        if self.game.playSeconds > 0 { return KeroFormat.playTime(self.game.playSeconds) + " played" }
        if let played = self.game.playedDate { return "Played " + KeroFormat.when(played).lowercasedFirst }
        return self.game.system.name
    }
}

private struct KeroCompactRow: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    var isFocused: Bool

    var body: some View
    {
        Button {
            KeroFeedback.select()
            self.model.openDetails(self.game)
        } label: {
            HStack(spacing: 12) {
                KeroGameCover(game: self.game, cornerRadius: 12, showsTitle: false)
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KeroTheme.stroke, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.game.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KeroTheme.primaryText)
                        .lineLimit(1)
                    Text(self.meta)
                        .font(.system(size: 12))
                        .foregroundStyle(KeroTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if self.game.isFavorite
                {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(KeroTheme.favorite)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KeroTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .background(self.isFocused ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(KeroPressStyle())
        .contextMenu { KeroGameMenuItems(model: self.model, game: self.game, includesDetails: true) }
        .accessibilityLabel(Text("\(self.game.name), \(self.meta)"))
    }

    /// "Game Boy Color · 汉化 · Last week"
    private var meta: String {
        var parts = [self.game.system.name]
        if self.game.isChineseTranslation { parts.append("汉化") }
        parts.append(self.game.playedDate.map { KeroFormat.when($0) } ?? "Never played")
        return parts.joined(separator: " · ")
    }
}
