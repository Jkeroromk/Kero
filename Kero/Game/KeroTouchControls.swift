//
//  KeroTouchControls.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftUI

import KeroEngine

/// On-screen controller. Each control tracks its own touch, so several can be held at once.
struct KeroTouchControls: View
{
    enum Layout
    {
        /// Below the screen, like a Game Boy.
        case portrait
        /// Over the sides of the screen.
        case landscape
    }

    var system: KeroSystem
    var layout: Layout
    var onChange: (KeroButtons) -> Void

    @State private var dpadButtons: KeroButtons = []
    @State private var heldButtons: KeroButtons = []

    private var hasShoulders: Bool {
        return self.system == .gameBoyAdvance || self.system == .snes
    }

    var body: some View
    {
        Group {
            switch self.layout
            {
            case .portrait: self.portrait
            case .landscape: self.landscape
            }
        }
        .onChange(of: self.dpadButtons) { _, _ in self.publish() }
        .onChange(of: self.heldButtons) { _, _ in self.publish() }
        .onDisappear { self.onChange([]) }
    }

    private func publish()
    {
        self.onChange(self.dpadButtons.union(self.heldButtons))
    }

    // MARK: Layouts

    private var portrait: some View {
        VStack(spacing: 18) {
            if self.hasShoulders
            {
                HStack {
                    self.shoulder("L", .l)
                    Spacer()
                    self.shoulder("R", .r)
                }
            }

            HStack(alignment: .center) {
                KeroDPad(buttons: self.$dpadButtons)
                    .frame(width: 150, height: 150)
                Spacer(minLength: 12)
                self.faceButtons
            }

            HStack(spacing: 28) {
                self.pill("SELECT", .select)
                self.pill("START", .start)
            }

            Spacer(minLength: 0)
        }
    }

    private var landscape: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                if self.hasShoulders { self.shoulder("L", .l) }
                Spacer()
                KeroDPad(buttons: self.$dpadButtons)
                    .frame(width: 140, height: 140)
                self.pill("SELECT", .select)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 16) {
                if self.hasShoulders { self.shoulder("R", .r) }
                Spacer()
                self.faceButtons
                self.pill("START", .start)
            }
        }
        .opacity(0.75)
    }

    private var faceButtons: some View {
        // Nintendo layout: A on the right, B lower-left.
        ZStack {
            self.round("B", .b)
                .offset(x: -38, y: 22)
            self.round("A", .a)
                .offset(x: 38, y: -22)
        }
        .frame(width: 160, height: 120)
    }

    // MARK: Controls

    private func round(_ title: String, _ button: KeroButtons) -> some View
    {
        KeroHoldable(isHeld: self.binding(for: button)) { isHeld in
            Text(title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(Circle().fill(Color.white.opacity(isHeld ? 0.45 : 0.18)))
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
        }
    }

    private func pill(_ title: String, _ button: KeroButtons) -> some View
    {
        KeroHoldable(isHeld: self.binding(for: button)) { isHeld in
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(isHeld ? 0.45 : 0.15)))
        }
    }

    private func shoulder(_ title: String, _ button: KeroButtons) -> some View
    {
        KeroHoldable(isHeld: self.binding(for: button)) { isHeld in
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 96, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(isHeld ? 0.45 : 0.15)))
        }
    }

    private func binding(for button: KeroButtons) -> Binding<Bool>
    {
        return Binding(
            get: { self.heldButtons.contains(button) },
            set: { isHeld in
                if isHeld { self.heldButtons.insert(button) } else { self.heldButtons.remove(button) }
            }
        )
    }
}

/// A view that reports whether a finger is on it, with a light haptic on press.
private struct KeroHoldable<Content: View>: View
{
    @Binding var isHeld: Bool
    @ViewBuilder var content: (Bool) -> Content

    var body: some View
    {
        self.content(self.isHeld)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !self.isHeld else { return }
                        self.isHeld = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onEnded { _ in self.isHeld = false }
            )
    }
}

/// D-pad that supports diagonals and sliding between directions.
private struct KeroDPad: View
{
    @Binding var buttons: KeroButtons

    var body: some View
    {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let arm = size / 3

            ZStack {
                // Cross shape
                Group {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(width: arm, height: size)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(width: size, height: arm)
                }
                .foregroundStyle(Color.white.opacity(0.16))

                self.arrow("chevron.up", active: self.buttons.contains(.up)).offset(y: -arm)
                self.arrow("chevron.down", active: self.buttons.contains(.down)).offset(y: arm)
                self.arrow("chevron.left", active: self.buttons.contains(.left)).offset(x: -arm)
                self.arrow("chevron.right", active: self.buttons.contains(.right)).offset(x: arm)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newButtons = self.directions(for: value.location, in: geometry.size)
                        if newButtons != self.buttons
                        {
                            if !newButtons.isEmpty { UISelectionFeedbackGenerator().selectionChanged() }
                            self.buttons = newButtons
                        }
                    }
                    .onEnded { _ in self.buttons = [] }
            )
        }
    }

    private func arrow(_ symbol: String, active: Bool) -> some View
    {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(.white.opacity(active ? 1 : 0.6))
    }

    private func directions(for location: CGPoint, in size: CGSize) -> KeroButtons
    {
        let dx = location.x - size.width / 2
        let dy = location.y - size.height / 2
        let deadZone = min(size.width, size.height) * 0.12

        guard hypot(dx, dy) > deadZone else { return [] }

        // 8-way: a direction counts when it's within 67.5° of the touch angle.
        let angle = Double(atan2(-dy, dx)) // 0 = right, counter-clockwise
        var result: KeroButtons = []
        let window = Double.pi * 3 / 8
        func near(_ target: Double) -> Bool
        {
            var delta = abs(angle - target)
            if delta > .pi { delta = 2 * .pi - delta }
            return delta < window
        }

        if near(0) { result.insert(.right) }
        if near(.pi / 2) { result.insert(.up) }
        if near(.pi) { result.insert(.left) }
        if near(-.pi / 2) { result.insert(.down) }
        return result
    }
}
