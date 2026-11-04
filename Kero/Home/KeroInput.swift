//
//  KeroInput.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Turns game controller and keyboard input into home-screen commands.
//  While a game is running, KeroEngine's KeroControllerInput owns the controllers;
//  the home screen re-attaches when it comes back.
//

import GameController
import UIKit

enum KeroCommand: Equatable
{
    case up
    case down
    case left
    case right
    case confirm
    case back
    case action        // X: favorite
    case resume        // Menu / Start: back into the running game
    case pageUp
    case pageDown

    var isDirectional: Bool {
        switch self
        {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }
}

@MainActor
final class KeroInputRouter
{
    var commandHandler: ((KeroCommand) -> Void)?
    var connectionHandler: ((Bool) -> Void)?

    /// Fire A / B / X on release instead of press, so a press that closes a menu over a running
    /// game (the pause menu) is over before the game gets the controller back.
    var firesButtonsOnRelease = false

    private(set) var isControllerConnected = false

    private var held = Set<String>()
    /// Buttons already down when we attached (e.g. the Home press that opened the pause menu):
    /// their release must not count as a press.
    private var suppressed = Set<String>()
    private var repeatTimer: Timer?
    private var repeatingCommand: KeroCommand?
    private var observers: [NSObjectProtocol] = []
    private var isRunning = false

    func start()
    {
        guard !self.isRunning else { return }
        self.isRunning = true

        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCKeyboardDidConnect]
        {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.attach() }
            })
        }

        self.attach()
    }

    func stop()
    {
        guard self.isRunning else { return }
        self.isRunning = false

        for observer in self.observers
        {
            NotificationCenter.default.removeObserver(observer)
        }
        self.observers.removeAll()

        // Leave the controller and keyboard handlers in place: by the time this runs (after
        // `isPlaying` flips), KeroEngine's KeroControllerInput has usually installed its own,
        // and clearing them here would leave the game with no input. Our handlers go inert
        // via the `isRunning` checks, and `attach()` replaces them when the home screen returns.

        self.stopRepeating()
        self.held.removeAll()
        self.suppressed.removeAll()
    }
}

private extension KeroInputRouter
{
    func attach()
    {
        guard self.isRunning else { return }

        let controllers = GCController.controllers()
        for controller in controllers
        {
            guard let gamepad = controller.extendedGamepad else { continue }

            for input in self.inputs(of: gamepad) where input.isPressed && !self.held.contains(input.key)
            {
                self.held.insert(input.key)
                self.suppressed.insert(input.key)
            }

            gamepad.valueChangedHandler = { [weak self] gamepad, _ in
                MainActor.assumeIsolated { self?.gamepadChanged(gamepad) }
            }
        }

        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            MainActor.assumeIsolated { self?.keyChanged(keyCode, pressed: pressed) }
        }

        let connected = controllers.contains { $0.extendedGamepad != nil }
        self.isControllerConnected = connected
        self.connectionHandler?(connected)
    }

    struct GamepadInput
    {
        var key: String
        var isPressed: Bool
        var command: KeroCommand
        var firesOnRelease = false
    }

    func inputs(of gamepad: GCExtendedGamepad) -> [GamepadInput]
    {
        let stick = gamepad.leftThumbstick
        let buttonsOnRelease = self.firesButtonsOnRelease

        // Same positional layout as in-game: right face button confirms, bottom goes back.
        return [
            GamepadInput(key: "up", isPressed: gamepad.dpad.up.isPressed || stick.yAxis.value > 0.6, command: .up),
            GamepadInput(key: "down", isPressed: gamepad.dpad.down.isPressed || stick.yAxis.value < -0.6, command: .down),
            GamepadInput(key: "left", isPressed: gamepad.dpad.left.isPressed || stick.xAxis.value < -0.6, command: .left),
            GamepadInput(key: "right", isPressed: gamepad.dpad.right.isPressed || stick.xAxis.value > 0.6, command: .right),
            GamepadInput(key: "confirm", isPressed: gamepad.buttonB.isPressed, command: .confirm, firesOnRelease: buttonsOnRelease),
            GamepadInput(key: "back", isPressed: gamepad.buttonA.isPressed, command: .back, firesOnRelease: buttonsOnRelease),
            GamepadInput(key: "action", isPressed: gamepad.buttonX.isPressed, command: .action, firesOnRelease: buttonsOnRelease),
            GamepadInput(key: "pageUp", isPressed: gamepad.leftShoulder.isPressed || gamepad.leftTrigger.isPressed, command: .pageUp),
            GamepadInput(key: "pageDown", isPressed: gamepad.rightShoulder.isPressed || gamepad.rightTrigger.isPressed, command: .pageDown),
            // Resume fires on release so the press doesn't leak into the game. Home does the same
            // as Menu here (in a game it opens the pause menu, so here it closes it again).
            GamepadInput(key: "resume", isPressed: gamepad.buttonMenu.isPressed, command: .resume, firesOnRelease: true),
            GamepadInput(key: "home", isPressed: gamepad.buttonHome?.isPressed == true, command: .resume, firesOnRelease: true),
        ]
    }

    func gamepadChanged(_ gamepad: GCExtendedGamepad)
    {
        guard self.isRunning else { return }

        for input in self.inputs(of: gamepad)
        {
            self.update(input.key, input.isPressed, input.command, firesOnRelease: input.firesOnRelease)
        }
    }

    func keyChanged(_ keyCode: GCKeyCode, pressed: Bool)
    {
        guard self.isRunning else { return }

        let command: KeroCommand?
        switch keyCode
        {
        case .upArrow, .keyW: command = .up
        case .downArrow, .keyS: command = .down
        case .leftArrow, .keyA: command = .left
        case .rightArrow, .keyD: command = .right
        case .returnOrEnter, .spacebar: command = .confirm
        case .escape, .deleteOrBackspace: command = .back
        case .keyF: command = .action
        case .keyQ: command = .pageUp
        case .keyE: command = .pageDown
        case .tab: command = .resume
        default: command = nil
        }

        guard let command else { return }
        let onRelease = command == .resume || (self.firesButtonsOnRelease && !command.isDirectional)
        self.update("key.\(keyCode.rawValue)", pressed, command, firesOnRelease: onRelease)
    }

    func update(_ key: String, _ isPressed: Bool, _ command: KeroCommand, firesOnRelease: Bool = false)
    {
        if isPressed
        {
            guard !self.held.contains(key) else { return }
            self.held.insert(key)

            guard !firesOnRelease else { return }
            self.commandHandler?(command)

            if command.isDirectional
            {
                self.startRepeating(command)
            }
        }
        else
        {
            guard self.held.contains(key) else { return }
            self.held.remove(key)

            if self.suppressed.remove(key) != nil
            {
                return
            }

            if firesOnRelease
            {
                self.commandHandler?(command)
            }

            if self.repeatingCommand == command
            {
                self.stopRepeating()
            }
        }
    }

    func startRepeating(_ command: KeroCommand)
    {
        self.stopRepeating()
        self.repeatingCommand = command

        // Console feel: short delay, then a steady repeat while held.
        self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.repeatingCommand == command else { return }

                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.repeatingCommand == command else { return }
                        self.commandHandler?(command)
                    }
                }
            }
        }
    }

    func stopRepeating()
    {
        self.repeatTimer?.invalidate()
        self.repeatTimer = nil
        self.repeatingCommand = nil
    }
}
