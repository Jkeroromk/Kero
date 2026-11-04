//
//  KeroHomeScreen.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftData
import SwiftUI

/// Connects home, library and game details to the library (SwiftData), the app model and controller input.
struct KeroHomeScreen: View
{
    @Environment(AppModel.self) private var appModel
    @Query private var games: [KeroGame]

    @StateObject private var model = KeroHomeModel()
    @State private var input = KeroInputRouter()

    /// Narrower than this (the folded outer display, or an iPhone held upright) gets the compact home.
    static let compactWidth: CGFloat = 560

    var body: some View
    {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < Self.compactWidth

            self.content(isCompact: isCompact)
                .onAppear { self.model.isCompact = isCompact }
                .onChange(of: isCompact) { _, isCompact in self.model.isCompact = isCompact }
        }
        .background(KeroTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            let model = self.model
            model.host = self.appModel
            self.appModel.gameWillBeDeleted = { [weak model] game in
                model?.gameWillBeDeleted(game)
            }
            self.model.update(games: self.games)
            self.configureInput()
            self.updateInputActivity()
        }
        .onChange(of: self.games) { _, games in
            self.model.update(games: games)
        }
        .onChange(of: self.appModel.isPlaying) { _, _ in
            self.model.refreshNowPlaying()
            self.updateInputActivity()
        }
        .onChange(of: self.appModel.isShowingSheet) { _, _ in
            self.updateInputActivity()
        }
    }

    @ViewBuilder
    private func content(isCompact: Bool) -> some View
    {
        if self.model.section == .details, let game = self.model.detailGame
        {
            KeroGameDetailView(model: self.model, game: game)
                .id(game.identifier)
                .transition(.opacity)
        }
        else if isCompact
        {
            KeroCompactHome(model: self.model)
                .transition(.opacity)
        }
        else if self.model.section == .library
        {
            KeroLibraryView(model: self.model)
                .transition(.opacity)
        }
        else
        {
            KeroConsoleHome(model: self.model)
                .transition(.opacity)
        }
    }

    private func configureInput()
    {
        let model = self.model

        self.input.commandHandler = { [weak model] command in
            model?.handle(command)
        }
        self.input.connectionHandler = { [weak model] isConnected in
            withAnimation(.easeInOut(duration: 0.2)) {
                model?.isControllerConnected = isConnected
                if isConnected { model?.showsFocus = true }
            }
        }
    }

    /// The home screen owns the controllers only while it's in front and no sheet is open.
    private func updateInputActivity()
    {
        if self.appModel.isPlaying || self.appModel.isShowingSheet
        {
            self.input.stop()
        }
        else
        {
            self.input.start()
        }
    }
}
