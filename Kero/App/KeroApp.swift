//
//  KeroApp.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftData
import SwiftUI
import UIKit

import KeroEngine

@main
struct KeroMain: App
{
    @State private var appModel = AppModel()

    init()
    {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene
    {
        WindowGroup {
            RootView()
                .environment(self.appModel)
        }
        .modelContainer(for: KeroGame.self)
    }
}

struct RootView: View
{
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View
    {
        @Bindable var appModel = self.appModel

        ZStack {
            KeroHomeScreen()

            if appModel.isPlaying, let session = appModel.session
            {
                GameView(session: session,
                         onHome: { appModel.returnHome() },
                         onQuit: { appModel.quitGame() })
                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity),
                                            removal: .scale(scale: 0.6).combined(with: .opacity)))
                    .zIndex(1)
            }
        }
        .onAppear {
            appModel.modelContext = self.modelContext
        }
        .fileImporter(isPresented: $appModel.isImporting,
                      allowedContentTypes: KeroLibrary.importableTypes,
                      allowsMultipleSelection: true) { result in
            appModel.handleImport(result)
        }
        .sheet(isPresented: $appModel.isShowingSettings) {
            SettingsView()
        }
        .alert("Delete \(appModel.gamePendingDeletion?.name ?? "game")?",
               isPresented: Binding(get: { appModel.gamePendingDeletion != nil },
                                    set: { if !$0 { appModel.gamePendingDeletion = nil } })) {
            Button("Delete", role: .destructive) { appModel.deletePendingGame() }
            Button("Cancel", role: .cancel) { appModel.gamePendingDeletion = nil }
        } message: {
            Text("The game file is removed. Its saves stay on this iPhone and come back if you import the same game again.")
        }
        .alert(appModel.message?.title ?? "",
               isPresented: Binding(get: { appModel.message != nil },
                                    set: { if !$0 { appModel.message = nil } })) {
            Button("OK", role: .cancel) { appModel.message = nil }
        } message: {
            Text(appModel.message?.text ?? "")
        }
        .onOpenURL { url in
            // "Open in Kero" from Files or AirDrop.
            appModel.importFiles([url])
        }
        .onChange(of: self.scenePhase) { _, phase in
            if phase != .active, appModel.isPlaying
            {
                appModel.session?.pauseForBackground()
            }
        }
    }
}
