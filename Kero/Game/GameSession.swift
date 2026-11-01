//
//  GameSession.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import GameController
import Observation
import SwiftUI

import KeroEngine

/// One loaded game: the emulator, its input, the pause menu and save states.
@MainActor
@Observable
final class GameSession
{
    let game: KeroGame
    let emulator: KeroEmulator
    let input: KeroControllerInput

    var isMenuVisible = false
    var isFastForwarding = false {
        didSet { self.emulator.speed = self.isFastForwarding ? 4 : 1 }
    }
    var isControllerConnected = false
    var hasSaveState = false
    var toast: String?

    @ObservationIgnored private let storage = KeroGameStorage.default
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    static let saveSlot = 1

    init(game: KeroGame) throws
    {
        self.game = game

        let saveURL = KeroGameStorage.default.batterySaveURL(forGame: game.identifier)
        self.emulator = try KeroEmulator(romURL: game.romURL, saveURL: saveURL)
        self.input = KeroControllerInput(emulator: self.emulator)

        self.hasSaveState = FileManager.default.fileExists(atPath: self.storage.saveStateURL(forGame: game.identifier, slot: Self.saveSlot).path)

        self.input.menuHandler = { [weak self] in
            self?.toggleMenu()
        }
        self.input.fastForwardHandler = { [weak self] isHeld in
            self?.isFastForwarding = isHeld
        }

        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect]
        {
            self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateControllerState() }
            })
        }
        self.updateControllerState()
    }

    deinit
    {
        for observer in self.observers
        {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var videoAspectRatio: CGFloat {
        let format = self.emulator.videoFormat
        return CGFloat(format.width) / CGFloat(max(1, format.height))
    }

    // MARK: Lifecycle

    func start()
    {
        self.emulator.start()
        self.input.start()
    }

    /// Going back to the home screen: pause, and hand the controllers back.
    func suspend()
    {
        self.isMenuVisible = false
        self.isFastForwarding = false
        self.emulator.pause()
        self.input.stop()
    }

    func resume()
    {
        self.isMenuVisible = false
        self.input.start()
        self.emulator.resume()
    }

    func stop()
    {
        self.input.stop()
        self.emulator.stop()
    }

    /// App went to the background: pause without dismissing the game screen.
    func pauseForBackground()
    {
        guard self.emulator.state == .running else { return }
        self.emulator.pause()
        self.isMenuVisible = true
    }

    /// iPhone Duo folded shut: pause, and remember whether to carry on when it opens.
    @ObservationIgnored private var resumesWhenLidOpens = false

    func closeLid()
    {
        guard self.emulator.state == .running else { return }
        self.isFastForwarding = false
        self.emulator.pause()
        self.resumesWhenLidOpens = true
    }

    func openLid()
    {
        guard self.resumesWhenLidOpens else { return }
        self.resumesWhenLidOpens = false
        if !self.isMenuVisible
        {
            self.emulator.resume()
        }
    }

    // MARK: Menu

    func toggleMenu()
    {
        if self.isMenuVisible
        {
            self.closeMenu()
        }
        else
        {
            self.isFastForwarding = false
            self.emulator.pause()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.isMenuVisible = true }
        }
    }

    func closeMenu()
    {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.isMenuVisible = false }
        self.emulator.resume()
    }

    func saveState()
    {
        Task {
            do
            {
                let data = try await self.emulator.saveState()
                try self.storage.writeSaveState(data, forGame: self.game.identifier, slot: Self.saveSlot)
                self.hasSaveState = true
                self.showToast("State saved")
            }
            catch
            {
                self.showToast(error.localizedDescription)
            }
        }
    }

    func loadState()
    {
        Task {
            do
            {
                let data = try self.storage.readSaveState(forGame: self.game.identifier, slot: Self.saveSlot)
                try await self.emulator.loadState(data)
                self.showToast("State loaded")
                self.closeMenu()
            }
            catch
            {
                self.showToast(error.localizedDescription)
            }
        }
    }

    func reset()
    {
        self.emulator.reset()
        self.closeMenu()
    }

    // MARK: Helpers

    private func updateControllerState()
    {
        self.isControllerConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    private func showToast(_ text: String)
    {
        self.toastTask?.cancel()
        withAnimation { self.toast = text }

        self.toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.toast = nil }
        }
    }
}
