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

                if self.session.game.system == .nintendoDS
                {
                    // One frame, two views: the top screen and the touch screen.
                    self.screen(source: KeroConsoleLayout.dsTopSource)
                        .frame(width: layout.screen.width, height: layout.screen.height)
                        .position(x: layout.screen.midX, y: layout.screen.midY)

                    self.screen(source: KeroConsoleLayout.dsBottomSource)
                        .frame(width: layout.bottomScreen.width, height: layout.bottomScreen.height)
                        .position(x: layout.bottomScreen.midX, y: layout.bottomScreen.midY)

                    KeroTouchScreen { point in
                        self.session.emulator.setTouch(point)
                    }
                    .frame(width: layout.bottomScreen.width, height: layout.bottomScreen.height)
                    .position(x: layout.bottomScreen.midX, y: layout.bottomScreen.midY)
                }
                else
                {
                    self.screen(source: CGRect(x: 0, y: 0, width: 1, height: 1))
                        .frame(width: layout.screen.width, height: layout.screen.height)
                        .position(x: layout.screen.midX, y: layout.screen.midY)
                }

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
                    Label("\(Int(self.session.fastForwardSpeed))×", systemImage: "forward.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .fixedSize()
                        .position(x: layout.screen.minX + 36, y: layout.screen.minY + 20)
                }

                if self.session.isMenuVisible
                {
                    KeroPauseMenu(session: self.session)
                        .frame(width: layout.size.width, height: layout.size.height)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(1)
                }

                if let toast = self.session.toast
                {
                    Text(toast)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KeroTheme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color(hex: 0x1A1C22, opacity: 0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(KeroTheme.strokeStrong, lineWidth: 1))
                        .fixedSize()
                        .position(x: self.session.isMenuVisible ? layout.size.width / 2 : layout.screen.midX,
                                  y: self.session.isMenuVisible ? max(28, geometry.safeAreaInsets.top + 18) : layout.screen.minY + 30)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .onAppear {
            self.session.onHome = self.onHome
            self.session.onQuit = self.onQuit
        }
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

    private func screen(source: CGRect) -> some View
    {
        KeroGameScreen(emulator: self.session.emulator, filter: self.filter, usesIntegerScaling: self.usesIntegerScaling, sourceRect: source)
    }
}
