//
//  KeroHomeView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Console-style home screen: pages of bubbles over an animated sky.
//

import SwiftUI

import KeroEngine

struct KeroHomeView: View
{
    @ObservedObject var model: KeroHomeModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var scrolledPage: Int? = nil

    var body: some View
    {
        let palette = KeroTheme.palette(for: self.colorScheme)

        ZStack {
            KeroBackground(palette: palette)

            VStack(spacing: 0) {
                KeroStatusBar(model: self.model, palette: palette)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                GeometryReader { geometry in
                    let layout = KeroGridLayout(size: geometry.size)

                    ZStack(alignment: .trailing) {
                        self.pages(layout: layout, palette: palette)

                        if self.model.pageCount > 1
                        {
                            KeroPageDots(count: self.model.pageCount, current: self.model.page, palette: palette)
                                .padding(.trailing, 8)
                        }
                    }
                    .onAppear {
                        self.model.layoutDidChange(columns: layout.columns, rows: layout.rows)
                        self.scrolledPage = self.model.page
                    }
                    .onChange(of: layout) { _, newLayout in
                        self.model.layoutDidChange(columns: newLayout.columns, rows: newLayout.rows)
                    }
                }

                if self.model.gameCount == 0
                {
                    KeroEmptyHint(palette: palette)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }

                KeroHintBar(model: self.model, palette: palette)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            if let game = self.model.liveAreaGame
            {
                KeroLiveArea(model: self.model, game: game, palette: palette)
                    .id(game.persistentModelID)
                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                            removal: .move(edge: .bottom).combined(with: .opacity)))
                    .zIndex(1)
            }
        }
        .onChange(of: self.model.page) { _, page in
            guard page != self.scrolledPage else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                self.scrolledPage = page
            }
        }
        .onChange(of: self.scrolledPage) { _, page in
            guard let page, page != self.model.page else { return }
            self.model.pageDidScroll(to: page)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

private extension KeroHomeView
{
    func pages(layout: KeroGridLayout, palette: KeroTheme.Palette) -> some View
    {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< self.model.pageCount, id: \.self) { page in
                    self.page(page, layout: layout, palette: palette)
                        .containerRelativeFrame(.vertical)
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: self.$scrolledPage)
    }

    func page(_ page: Int, layout: KeroGridLayout, palette: KeroTheme.Palette) -> some View
    {
        let tiles = Array(self.model.tiles(onPage: page))
        let firstIndex = page * self.model.tilesPerPage

        return VStack(spacing: layout.rowSpacing) {
            ForEach(0 ..< layout.rows, id: \.self) { row in
                HStack(alignment: .top, spacing: layout.columnSpacing) {
                    ForEach(0 ..< layout.columns, id: \.self) { column in
                        let localIndex = row * layout.columns + column

                        if localIndex < tiles.count
                        {
                            let tile = tiles[localIndex]
                            let index = firstIndex + localIndex

                            KeroBubble(tile: tile,
                                       diameter: layout.diameter,
                                       isFocused: self.model.showsFocus && self.model.focusedIndex == index,
                                       isRunning: self.isRunning(tile),
                                       palette: palette)
                                .frame(width: layout.cellWidth, height: layout.cellHeight, alignment: .top)
                                // Every other column sits a little lower, for a looser, floating arrangement.
                                .offset(y: column.isMultiple(of: 2) ? 0 : layout.diameter * 0.16)
                                .onTapGesture {
                                    KeroFeedback.select()
                                    self.model.select(tile)
                                }
                                .contextMenu { self.contextMenu(for: tile) }
                        }
                        else
                        {
                            Color.clear.frame(width: layout.cellWidth, height: layout.cellHeight)
                        }
                    }
                }
            }
        }
        .padding(.top, layout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    func isRunning(_ tile: KeroTile) -> Bool
    {
        guard case .game(let game) = tile else { return false }
        return self.model.isRunning(game)
    }

    @ViewBuilder
    func contextMenu(for tile: KeroTile) -> some View
    {
        if case .game(let game) = tile
        {
            Button {
                self.model.perform(.start, for: game)
            } label: {
                Label(self.model.isRunning(game) ? "Resume" : "Start", systemImage: "play.fill")
            }

            Button {
                self.model.toggleFavorite(game)
            } label: {
                Label(game.isFavorite ? "Remove Favorite" : "Favorite", systemImage: game.isFavorite ? "star.slash" : "star")
            }

            Button(role: .destructive) {
                self.model.perform(.delete, for: game)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Layout -

struct KeroGridLayout: Equatable
{
    var diameter: CGFloat
    var columns: Int
    var rows: Int
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat
    var topInset: CGFloat

    init(size: CGSize)
    {
        let shortSide = max(1, min(size.width, size.height))
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        self.diameter = min(isPad ? 132 : 96, max(62, shortSide * (isPad ? 0.2 : 0.19)))

        let labelHeight = min(15, max(11, self.diameter * 0.15)) * 2.6
        self.cellWidth = self.diameter * 1.38
        self.cellHeight = self.diameter * 1.16 + labelHeight + self.diameter * 0.16

        let horizontalMargin: CGFloat = 20
        self.columnSpacing = self.diameter * 0.12
        self.rowSpacing = self.diameter * 0.08
        self.topInset = self.diameter * 0.22

        let availableWidth = max(self.cellWidth, size.width - horizontalMargin * 2)
        self.columns = max(1, Int((availableWidth + self.columnSpacing) / (self.cellWidth + self.columnSpacing)))

        let availableHeight = max(self.cellHeight, size.height - self.topInset)
        self.rows = max(1, Int((availableHeight + self.rowSpacing) / (self.cellHeight + self.rowSpacing)))
    }
}

// MARK: - Status Bar -

struct KeroStatusBar: View
{
    @ObservedObject var model: KeroHomeModel
    let palette: KeroTheme.Palette

    var body: some View
    {
        HStack(spacing: 12) {
            Text("Kero")
                .font(KeroTheme.font(15, .heavy))
                .foregroundStyle(self.palette.text)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            Spacer(minLength: 8)

            if let nowPlaying = self.model.nowPlayingGame
            {
                Button {
                    self.model.host?.resumeNowPlaying()
                } label: {
                    HStack(spacing: 8) {
                        KeroRunningBadge(size: 18)
                        Text(nowPlaying.name)
                            .font(KeroTheme.font(14, .semibold))
                            .lineLimit(1)
                        if self.model.isControllerConnected
                        {
                            KeroButtonGlyph(label: "START", palette: self.palette)
                        }
                    }
                    .foregroundStyle(self.palette.text)
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .padding(.vertical, 5)
                    .keroGlass(Capsule(), palette: self.palette)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Resume \(nowPlaying.name)"))

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                if self.model.isControllerConnected
                {
                    Image(systemName: "gamecontroller.fill")
                }

                TimelineView(.everyMinute) { context in
                    HStack(spacing: 10) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .monospacedDigit()
                        KeroBatteryView()
                    }
                }
            }
            .font(KeroTheme.font(14, .semibold))
            .foregroundStyle(self.palette.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keroGlass(Capsule(), palette: self.palette)
        }
        .frame(height: 40)
    }
}

struct KeroBatteryView: View
{
    var body: some View
    {
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState

        if level >= 0
        {
            HStack(spacing: 4) {
                Image(systemName: self.symbolName(level: level, charging: state == .charging || state == .full))
                Text("\(Int((level * 100).rounded()))%")
                    .monospacedDigit()
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

// MARK: - Hints -

struct KeroButtonGlyph: View
{
    var label: String
    var palette: KeroTheme.Palette

    var body: some View
    {
        let isWide = self.label.count > 1

        Text(self.label)
            .font(KeroTheme.font(isWide ? 9 : 12, .heavy))
            .foregroundStyle(self.palette.skyTop)
            .padding(.horizontal, isWide ? 6 : 0)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.white, in: isWide ? AnyShape(Capsule()) : AnyShape(Circle()))
    }
}

struct KeroHintBar: View
{
    @ObservedObject var model: KeroHomeModel
    let palette: KeroTheme.Palette

    var body: some View
    {
        HStack {
            Spacer(minLength: 0)

            if self.model.isControllerConnected
            {
                HStack(spacing: 18) {
                    if self.model.liveAreaGame != nil
                    {
                        self.hint("A", "Select")
                        self.hint("Y", "Favorite")
                        self.hint("B", "Back")
                    }
                    else
                    {
                        self.hint("A", "Open")
                        self.hint("Y", "Favorite")
                        self.hint("L/R", "Page")
                        if self.model.nowPlayingGame != nil
                        {
                            self.hint("START", "Resume")
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(red: 0, green: 0.12, blue: 0.31).opacity(0.22), in: Capsule())
                .keroGlass(Capsule(), palette: self.palette)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(minHeight: 8)
        .animation(.easeInOut(duration: 0.2), value: self.model.isControllerConnected)
    }

    private func hint(_ button: String, _ title: LocalizedStringKey) -> some View
    {
        HStack(spacing: 6) {
            KeroButtonGlyph(label: button, palette: self.palette)
            Text(title)
                .font(KeroTheme.font(13, .semibold))
                .foregroundStyle(self.palette.text)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
    }
}

struct KeroPageDots: View
{
    var count: Int
    var current: Int
    var palette: KeroTheme.Palette

    var body: some View
    {
        VStack(spacing: 8) {
            ForEach(0 ..< self.count, id: \.self) { page in
                Capsule()
                    .fill(Color.white.opacity(page == self.current ? 0.95 : 0.4))
                    .frame(width: 6, height: page == self.current ? 18 : 6)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .keroGlass(Capsule(), palette: self.palette)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: self.current)
        .accessibilityElement()
        .accessibilityLabel(Text("Page \(self.current + 1) of \(self.count)"))
    }
}

struct KeroEmptyHint: View
{
    let palette: KeroTheme.Palette

    var body: some View
    {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(self.palette.text)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your shelf is empty")
                    .font(KeroTheme.font(16, .bold))
                Text("Tap Import to add game files you own (.gba, .gbc, .nes, .sfc, .z64, .md…).")
                    .font(KeroTheme.font(13, .medium))
                    .foregroundStyle(self.palette.secondaryText)
            }
            .foregroundStyle(self.palette.text)

            Spacer(minLength: 0)
        }
        .padding(14)
        .keroGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), palette: self.palette)
        .frame(maxWidth: 520)
    }
}
