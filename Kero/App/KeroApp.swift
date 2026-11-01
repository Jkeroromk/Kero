//
//  KeroApp.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import PhotosUI
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

    @State private var foldMonitor = KeroFoldMonitor()
    @State private var coverSelection: PhotosPickerItem?
    @AppStorage("foldedBehavior") private var foldedBehavior = "lid"
    @AppStorage("lidColor") private var lidColor = KeroLidColor.graphite.rawValue

    private var showsLid: Bool {
        return self.foldMonitor.isFolded && self.foldedBehavior == "lid"
    }

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

            if self.showsLid
            {
                KeroLidView(color: KeroLidColor(rawValue: self.lidColor) ?? .graphite,
                            gameName: appModel.session?.game.name)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background {
            // Full-window size, to notice iPhone Duo moving between its inner and outer displays.
            GeometryReader { geometry in
                Color.clear
                    .onAppear { self.foldMonitor.update(size: geometry.size) }
                    .onChange(of: geometry.size) { _, size in self.foldMonitor.update(size: size) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: self.showsLid) { _, closed in
            if closed
            {
                appModel.session?.closeLid()
            }
            else
            {
                appModel.session?.openLid()
            }
        }
        .onAppear {
            appModel.modelContext = self.modelContext
            KeroLibrary.tidyNames(in: self.modelContext)
            Task { await KeroLibrary.refreshMetadata(in: self.modelContext) }
        }
        .sheet(isPresented: $appModel.isShowingAddGames) {
            KeroAddGamesView()
                .environment(appModel)
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
        .photosPicker(isPresented: Binding(get: { appModel.gamePendingCover != nil },
                                           set: { if !$0 && self.coverSelection == nil { appModel.gamePendingCover = nil } }),
                      selection: self.$coverSelection,
                      matching: .images)
        .onChange(of: self.coverSelection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self)
                {
                    appModel.setCover(data)
                }
                else
                {
                    appModel.gamePendingCover = nil
                }
                self.coverSelection = nil
            }
        }
        .alert("Rename Game",
               isPresented: Binding(get: { appModel.gamePendingRename != nil },
                                    set: { if !$0 { appModel.gamePendingRename = nil } })) {
            TextField("Name", text: $appModel.renameText)
                .submitLabel(.done)
            Button("Save") { appModel.commitRename() }
            Button("Cancel", role: .cancel) { appModel.gamePendingRename = nil }
        }
        .alert(appModel.message?.title ?? "",
               isPresented: Binding(get: { appModel.message != nil },
                                    set: { if !$0 { appModel.message = nil } })) {
            Button("OK", role: .cancel) { appModel.message = nil }
        } message: {
            Text(appModel.message?.text ?? "")
        }
        .onOpenURL { url in
            // "Open in Kero" from Files or AirDrop. iOS hands us a copy in Documents/Inbox;
            // the library keeps its own copy, so drop the Inbox one afterwards.
            appModel.importAndReport([url]) {
                KeroLibrary.removeInboxCopy(url)
            }
        }
        .onChange(of: self.scenePhase) { _, phase in
            if phase != .active, appModel.isPlaying
            {
                appModel.session?.pauseForBackground()
            }
        }
    }
}
