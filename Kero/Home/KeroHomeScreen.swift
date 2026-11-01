//
//  KeroHomeScreen.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftData
import SwiftUI

/// Connects the bubble home screen to the library (SwiftData), the app model and controller input.
struct KeroHomeScreen: View
{
    @Environment(AppModel.self) private var appModel
    @Query private var games: [KeroGame]

    @StateObject private var model = KeroHomeModel()
    @State private var input = KeroInputRouter()

    var body: some View
    {
        KeroHomeView(model: self.model)
            .onAppear {
                self.model.host = self.appModel
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
