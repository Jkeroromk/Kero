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
    @AppStorage("landscapeLayout") private var landscapeLayout = "console"

    private var filter: KeroVideoFilter {
        KeroVideoFilter(rawValue: self.filterRawValue) ?? .sharp
    }

    private var showsTouchControls: Bool {
        return self.alwaysShowTouchControls || !self.session.isControllerConnected
    }

    var body: some View
    {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let layout = self.layout(size: geometry.size, insets: insets)

            ZStack(alignment: .topLeading) {
                if layout.hasShell
                {
                    KeroConsoleShell(layout: layout, system: self.session.game.system, isRunning: !self.session.isMenuVisible)
                }
                else
                {
                    Color.black
                }

                self.screen
                    .frame(width: layout.screen.width, height: layout.screen.height)
                    .position(x: layout.screen.midX, y: layout.screen.midY)

                if layout.hasControls
                {
                    KeroTouchController(layout: layout, system: self.session.game.system, onChange: { self.session.input.touchButtons = $0 })
                        .frame(width: layout.size.width, height: layout.size.height)
                }

                KeroHomeButton(isOverlay: !layout.hasShell) {
                    self.session.toggleMenu()
                }
                .frame(width: layout.menu.width, height: layout.menu.height)
                .position(x: layout.menu.midX, y: layout.menu.midY)

                if self.session.isFastForwarding
                {
                    Label("4×", systemImage: "forward.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .fixedSize()
                        .position(x: layout.screen.minX + 36, y: layout.screen.minY + 20)
                }

                if let toast = self.session.toast
                {
                    Text(toast)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .fixedSize()
                        .position(x: layout.screen.midX, y: layout.screen.minY + 30)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if self.session.isMenuVisible
                {
                    PauseMenu(session: self.session, onHome: self.onHome, onQuit: self.onQuit)
                        .frame(width: layout.size.width, height: layout.size.height)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }

    /// `size` is the whole screen (safe areas ignored); `insets` are the safe areas to keep clear.
    private func layout(size: CGSize, insets: EdgeInsets) -> KeroConsoleLayout
    {
        let style: KeroConsoleLayout.Style
        if !self.showsTouchControls
        {
            style = .screenOnly
        }
        else if size.width > size.height
        {
            style = self.landscapeLayout == "fullscreen" ? .overlay : .landscape
        }
        else
        {
            style = .portrait
        }

        return KeroConsoleLayout.make(style: style, size: size, insets: insets,
                                      aspect: self.session.videoAspectRatio, system: self.session.game.system)
    }

    private var screen: some View {
        KeroGameScreen(emulator: self.session.emulator, filter: self.filter, usesIntegerScaling: self.usesIntegerScaling)
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
