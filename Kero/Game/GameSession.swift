//
//  GameSession.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import GameController
import Observation
import SwiftUI
import UIKit

import KeroEngine

/// One loaded game: the emulator, its input, the pause menu, save states and play time.
@MainActor
@Observable
final class GameSession
{
    let game: KeroGame
    let emulator: KeroEmulator
    let input: KeroControllerInput

    var isMenuVisible = false {
        didSet {
            guard self.isMenuVisible != oldValue else { return }
            self.updateMenuInput()
        }
    }
    var isFastForwarding = false {
        didSet { self.emulator.speed = self.isFastForwarding ? self.fastForwardSpeed : 1 }
    }
    /// Speed while fast-forwarding (2–8×). Persisted.
    var fastForwardSpeed: Double {
        didSet {
            UserDefaults.standard.set(self.fastForwardSpeed, forKey: Self.fastForwardSpeedKey)
            if self.isFastForwarding { self.emulator.speed = self.fastForwardSpeed }
        }
    }
    /// 0–100. Persisted.
    var volume: Double {
        didSet {
            UserDefaults.standard.set(self.volume, forKey: Self.volumeKey)
            self.emulator.volume = Float(self.volume / 100)
        }
    }
    var isControllerConnected = false
    var toast: String?

    /// Time played since this game was loaded, for the pause menu.
    private(set) var sessionSeconds: Double = 0

    /// Controller focus in the pause menu.
    var menuFocus: KeroPauseFocus = .resume

    /// Set by the game screen, so controller commands in the pause menu can go home or quit.
    @ObservationIgnored var onHome: (() -> Void)?
    @ObservationIgnored var onQuit: (() -> Void)?

    @ObservationIgnored let saveStates = KeroSaveStates.shared
    @ObservationIgnored private let menuInput = KeroInputRouter()
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var runningSince: Date?
    @ObservationIgnored private var playTimeTimer: Timer?

    static let fastForwardSpeedKey = "fastForwardSpeed"
    static let volumeKey = "gameVolume"

    init(game: KeroGame) throws
    {
        self.game = game

        let saveURL = KeroGameStorage.default.batterySaveURL(forGame: game.identifier)
        self.emulator = try KeroEmulator(romURL: game.romURL, saveURL: saveURL)
        self.input = KeroControllerInput(emulator: self.emulator)

        let defaults = UserDefaults.standard
        self.fastForwardSpeed = min(8, max(2, defaults.object(forKey: Self.fastForwardSpeedKey) as? Double ?? 4))
        self.volume = min(100, max(0, defaults.object(forKey: Self.volumeKey) as? Double ?? 100))
        self.emulator.volume = Float(self.volume / 100)

        self.input.menuHandler = { [weak self] in
            self?.toggleMenu()
        }
        self.input.fastForwardHandler = { [weak self] isHeld in
            self?.isFastForwarding = isHeld
        }

        self.menuInput.firesButtonsOnRelease = true
        self.menuInput.commandHandler = { [weak self] command in
            self?.handleMenuCommand(command)
        }

        self.emulator.stateDidChange = { [weak self] state in
            MainActor.assumeIsolated { self?.emulatorStateChanged(state) }
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

    var hasSaveState: Bool {
        return self.saveStates.latest(for: self.game.identifier) != nil
    }

    // MARK: Lifecycle

    func start()
    {
        self.isActive = true
        self.emulator.start()
        self.input.start()
    }

    /// Going back to the home screen: pause, and hand the controllers back.
    func suspend()
    {
        self.isActive = false
        self.isMenuVisible = false
        self.isFastForwarding = false
        self.emulator.pause()
        self.input.stop()
        self.menuInput.stop()
    }

    func resume()
    {
        self.isActive = true
        self.isMenuVisible = false
        self.menuInput.stop()
        self.input.start()
        self.emulator.resume()
    }

    func stop()
    {
        self.isActive = false
        self.commitPlayTime()
        self.runningSince = nil
        self.playTimeTimer?.invalidate()
        self.playTimeTimer = nil
        self.menuInput.stop()
        self.input.stop()
        self.emulator.stop()
    }

    /// App went to the background: pause without dismissing the game screen, and write the auto save.
    func pauseForBackground()
    {
        guard self.emulator.state == .running else { return }
        self.isFastForwarding = false
        self.emulator.pause()
        self.isMenuVisible = true
        self.autoSave(reason: .background)
    }

    /// iPhone Duo folded shut: pause, write the auto save, and remember whether to carry on when it opens.
    @ObservationIgnored private var resumesWhenLidOpens = false

    func closeLid()
    {
        guard self.emulator.state == .running else { return }
        self.isFastForwarding = false
        self.emulator.pause()
        self.resumesWhenLidOpens = true
        self.autoSave(reason: .folded)
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
            self.menuFocus = .resume
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.isMenuVisible = true }
        }
    }

    func closeMenu()
    {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.isMenuVisible = false }
        self.emulator.resume()
    }

    /// While the pause menu shows, controllers drive the menu instead of the game.
    private func updateMenuInput()
    {
        guard self.isActive else { return }

        if self.isMenuVisible
        {
            self.input.stop()
            self.menuInput.start()
        }
        else
        {
            self.menuInput.stop()
            self.input.start()
        }
    }

    // MARK: Save states

    /// "Save state": the slot saved to last (or Slot 1).
    func quickSave()
    {
        let slot = self.saveStates.quickSaveSlot(gameID: self.game.identifier)
        self.save(to: slot, toast: "Saved to \(KeroSaveStates.name(of: slot))")
    }

    /// "Save to a new slot": the next empty slot, otherwise the oldest one.
    func saveToNewSlot()
    {
        let target = self.saveStates.slotForNewSave(gameID: self.game.identifier)
        let name = KeroSaveStates.name(of: target.slot)
        let toast = target.replaces == nil ? "Saved to \(name)" : "Saved to \(name), replacing its oldest state"
        self.save(to: target.slot, toast: toast)
    }

    func save(to slot: Int, reason: KeroSaveState.Reason = .manual, toast: String? = nil, completion: (() -> Void)? = nil)
    {
        // The picture is the paused frame, taken now, before anything else runs.
        let thumbnail = KeroFrameSnapshot.pngData(from: self.emulator.frameBuffer)
        let gameID = self.game.identifier

        Task {
            do
            {
                let data = try await self.emulator.saveState()
                try self.saveStates.write(data, thumbnail: thumbnail, gameID: gameID, slot: slot, reason: reason)
                if let toast { self.showToast(toast) }
            }
            catch
            {
                if reason == .manual { self.showToast(error.localizedDescription) }
            }
            completion?()
        }
    }

    func loadLatestState()
    {
        guard let latest = self.saveStates.latest(for: self.game.identifier) else { return }
        self.loadState(slot: latest.slot)
    }

    /// Loads a slot and carries on playing.
    func loadState(slot: Int, closesMenu: Bool = true)
    {
        Task {
            do
            {
                let data = try self.saveStates.data(for: self.game.identifier, slot: slot)
                try await self.emulator.loadState(data)
                self.showToast("Loaded \(KeroSaveStates.name(of: slot))")
                if closesMenu && self.isMenuVisible { self.closeMenu() }
            }
            catch
            {
                self.showToast("Couldn't load \(KeroSaveStates.name(of: slot))")
            }
        }
    }

    private func autoSave(reason: KeroSaveState.Reason)
    {
        // The app may be suspended right after this; ask for a moment to finish writing.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Kero auto save", expirationHandler: nil)
        self.save(to: KeroSaveStates.autoSlot, reason: reason) {
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
    }

    func reset()
    {
        self.emulator.reset()
        self.closeMenu()
    }

    // MARK: Play time

    private func emulatorStateChanged(_ state: KeroEmulator.State)
    {
        switch state
        {
        case .running:
            if self.runningSince == nil { self.runningSince = Date() }
            if self.playTimeTimer == nil
            {
                // Bank the time now and then, so a crash or a force-quit loses at most a minute.
                self.playTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.commitPlayTime(restarting: true) }
                }
            }

        case .paused, .stopped:
            self.commitPlayTime()
            self.runningSince = nil
            self.playTimeTimer?.invalidate()
            self.playTimeTimer = nil
        }
    }

    private func commitPlayTime(restarting: Bool = false)
    {
        guard let since = self.runningSince else { return }

        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(since))
        self.runningSince = restarting ? now : nil
        guard elapsed > 0 else { return }

        self.sessionSeconds += elapsed
        if self.game.modelContext != nil && !self.game.isDeleted
        {
            self.game.playSeconds += elapsed
            self.game.playedDate = now
            try? self.game.modelContext?.save()
        }
    }

    // MARK: Helpers

    private func updateControllerState()
    {
        self.isControllerConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    func showToast(_ text: String)
    {
        self.toastTask?.cancel()
        withAnimation { self.toast = text }

        self.toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.toast = nil }
        }
    }
}
