//
//  GameView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftUI

import KeroEngine

/// Full-screen game: video, on-screen controls (when no controller is connected) and the pause menu.
struct GameView: View
{
    @Bindable var session: GameSession
    var onHome: () -> Void
    var onQuit: () -> Void

    @AppStorage("videoFilter") private var filterRawValue = KeroVideoFilter.sharp.rawValue
    @AppStorage("integerScaling") private var usesIntegerScaling = false
    @AppStorage("alwaysShowTouchControls") private var alwaysShowTouchControls = false

    private var filter: KeroVideoFilter {
        KeroVideoFilter(rawValue: self.filterRawValue) ?? .sharp
    }

    private var showsTouchControls: Bool {
        return self.alwaysShowTouchControls || !self.session.isControllerConnected
    }

    var body: some View
    {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscape
                {
                    self.screen
                        .ignoresSafeArea()

                    if self.showsTouchControls
                    {
                        KeroTouchController(system: self.session.game.system, layout: .landscape, onChange: { self.session.input.touchButtons = $0 })
                            .ignoresSafeArea()
                    }
                }
                else
                {
                    VStack(spacing: 0) {
                        self.screen
                            .aspectRatio(self.session.videoAspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)

                        if self.showsTouchControls
                        {
                            KeroTouchController(system: self.session.game.system, layout: .portrait, onChange: { self.session.input.touchButtons = $0 })
                                .frame(maxWidth: 560)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        else
                        {
                            Spacer(minLength: 0)
                        }
                    }
                }

                self.menuButton
                    // Landscape: top centre, clear of the L/R shoulder buttons.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLandscape ? .top : .topTrailing)
                    .padding(.top, isLandscape ? 8 : 0)
                    .padding(.trailing, isLandscape ? 0 : 12)

                if self.session.isFastForwarding
                {
                    Label("4×", systemImage: "forward.fill")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                }

                if let toast = self.session.toast
                {
                    Text(toast)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if self.session.isMenuVisible
                {
                    PauseMenu(session: self.session, onHome: self.onHome, onQuit: self.onQuit)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(1)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }

    private var screen: some View {
        KeroGameScreen(emulator: self.session.emulator, filter: self.filter, usesIntegerScaling: self.usesIntegerScaling)
    }

    private var menuButton: some View {
        Button {
            self.session.toggleMenu()
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial.opacity(0.7), in: Circle())
        }
        .accessibilityLabel("Pause")
    }
}

// MARK: - Pause Menu -

private struct PauseMenu: View
{
    @Bindable var session: GameSession
    var onHome: () -> Void
    var onQuit: () -> Void

    @AppStorage("videoFilter") private var filterRawValue = KeroVideoFilter.sharp.rawValue

    var body: some View
    {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { self.session.closeMenu() }

            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(self.session.game.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(self.session.game.system.name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    self.item("Resume", "play.fill", tint: .green) { self.session.closeMenu() }
                    self.item("Save State", "square.and.arrow.down.fill", tint: .blue) { self.session.saveState() }
                    self.item("Load State", "square.and.arrow.up.fill", tint: .blue, disabled: !self.session.hasSaveState) { self.session.loadState() }
                    self.item(self.session.isFastForwarding ? "Normal Speed" : "Fast Forward", "forward.fill", tint: .orange) {
                        self.session.isFastForwarding.toggle()
                        self.session.closeMenu()
                    }
                    self.item("Reset", "arrow.counterclockwise", tint: .orange) { self.session.reset() }
                    self.item("Home", "house.fill", tint: .teal) { self.onHome() }
                    self.item("Quit Game", "xmark", tint: .red) { self.onQuit() }
                }
                .frame(maxWidth: 460)

                Picker("Screen", selection: self.$filterRawValue) {
                    ForEach(KeroVideoFilter.allCases, id: \.rawValue) { filter in
                        Text(filter.name).tag(filter.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(24)
        }
    }

    private func item(_ title: String, _ symbol: String, tint: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.gradient))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
