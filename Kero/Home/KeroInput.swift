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
    case action        // Y: favorite
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

    private(set) var isControllerConnected = false

    private var held = Set<String>()
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

        for controller in GCController.controllers()
        {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil

        self.stopRepeating()
        self.held.removeAll()
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
            controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
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

    func gamepadChanged(_ gamepad: GCExtendedGamepad)
    {
        let stick = gamepad.leftThumbstick

        // Same positional layout as in-game: right face button confirms, bottom goes back.
        self.update("up", gamepad.dpad.up.isPressed || stick.yAxis.value > 0.6, .up)
        self.update("down", gamepad.dpad.down.isPressed || stick.yAxis.value < -0.6, .down)
        self.update("left", gamepad.dpad.left.isPressed || stick.xAxis.value < -0.6, .left)
        self.update("right", gamepad.dpad.right.isPressed || stick.xAxis.value > 0.6, .right)
        self.update("confirm", gamepad.buttonB.isPressed, .confirm)
        self.update("back", gamepad.buttonA.isPressed, .back)
        self.update("action", gamepad.buttonX.isPressed, .action)
        self.update("pageUp", gamepad.leftShoulder.isPressed || gamepad.leftTrigger.isPressed, .pageUp)
        self.update("pageDown", gamepad.rightShoulder.isPressed || gamepad.rightTrigger.isPressed, .pageDown)
        // Resume fires on release so the press doesn't leak into the game.
        self.update("resume", gamepad.buttonMenu.isPressed, .resume, firesOnRelease: true)
    }

    func keyChanged(_ keyCode: GCKeyCode, pressed: Bool)
    {
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
        self.update("key.\(keyCode.rawValue)", pressed, command, firesOnRelease: command == .resume)
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
