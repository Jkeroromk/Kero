//
//  KeroPauseMenu.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  The pause menu over a running game: resume and the usual actions on the left, screen filter,
//  fast-forward speed and volume below them, and the save-state slots on the right.
//  Touch, or a controller (D-pad / stick to move, A to choose, B or Menu to resume).
//

import SwiftUI

import KeroEngine

enum KeroPauseAction: Int, CaseIterable
{
    case saveState
    case loadState
    case fastForward
    case restart
    case home
    case quit

    var title: String {
        switch self
        {
        case .saveState: return "Save state"
        case .loadState: return "Load state"
        case .fastForward: return "Fast forward"
        case .restart: return "Restart"
        case .home: return "Home"
        case .quit: return "Quit game"
        }
    }

    var symbol: String {
        switch self
        {
        case .saveState: return "arrow.down.to.line"
        case .loadState: return "arrow.up.to.line"
        case .fastForward: return "forward.fill"
        case .restart: return "arrow.counterclockwise"
        case .home: return "house"
        case .quit: return "xmark"
        }
    }
}

enum KeroPauseFocus: Hashable
{
    case resume
    case action(KeroPauseAction)
    case filter
    case speed
    case volume
    /// Index into the listed save states (newest first).
    case slot(Int)
    case newSlot
}

// MARK: - Controller -

extension GameSession
{
    var menuStates: [KeroSaveState] {
        return self.saveStates.states(for: self.game.identifier)
    }

    func handleMenuCommand(_ command: KeroCommand)
    {
        guard self.isMenuVisible else { return }
        if !self.menuUsesFocus { self.menuUsesFocus = true }

        switch command
        {
        case .resume, .back:
            self.closeMenu()

        case .confirm:
            KeroFeedback.select()
            self.activate(self.menuFocus)

        case .up, .down, .left, .right:
            withAnimation(KeroTheme.focusSpring) { self.moveMenuFocus(command) }

        case .action, .pageUp, .pageDown:
            break
        }
    }

    func activate(_ focus: KeroPauseFocus)
    {
        switch focus
        {
        case .resume: self.closeMenu()
        case .action(let action): self.perform(action)
        case .filter: self.stepFilter(by: 1)
        case .speed, .volume: break
        case .slot(let index):
            let states = self.menuStates
            if states.indices.contains(index) { self.loadState(slot: states[index].slot) }
        case .newSlot: self.saveToNewSlot()
        }
    }

    func perform(_ action: KeroPauseAction)
    {
        switch action
        {
        case .saveState: self.quickSave()
        case .loadState: self.loadLatestState()
        case .fastForward:
            self.closeMenu()
            self.isFastForwarding.toggle()
        case .restart: self.reset()
        case .home: self.onHome?()
        case .quit: self.onQuit?()
        }
    }

    private func moveMenuFocus(_ command: KeroCommand)
    {
        let stateCount = self.menuStates.count
        let panelTop: KeroPauseFocus = stateCount > 0 ? .slot(0) : .newSlot
        var next: KeroPauseFocus?

        switch self.menuFocus
        {
        case .resume:
            switch command
            {
            case .down: next = .action(.saveState)
            case .right: next = panelTop
            default: break
            }

        case .action(let action):
            let index = action.rawValue
            let column = index % 2, row = index / 2
            switch command
            {
            case .left: next = column == 1 ? KeroPauseAction(rawValue: index - 1).map { .action($0) } : nil
            case .right: next = column == 0 ? KeroPauseAction(rawValue: index + 1).map { .action($0) } : panelTop
            case .up: next = row == 0 ? .resume : KeroPauseAction(rawValue: index - 2).map { .action($0) }
            case .down: next = row == 2 ? .filter : KeroPauseAction(rawValue: index + 2).map { .action($0) }
            default: break
            }

        case .filter:
            switch command
            {
            case .up: next = .action(.home)
            case .down: next = .speed
            case .left: self.stepFilter(by: -1); return
            case .right: self.stepFilter(by: 1); return
            default: break
            }

        case .speed:
            switch command
            {
            case .up: next = .filter
            case .down: next = .volume
            case .left: self.fastForwardSpeed = max(2, self.fastForwardSpeed - 1); KeroFeedback.move(); return
            case .right: self.fastForwardSpeed = min(8, self.fastForwardSpeed + 1); KeroFeedback.move(); return
            default: break
            }

        case .volume:
            switch command
            {
            case .up: next = .speed
            case .left: self.volume = max(0, self.volume - 10); KeroFeedback.move(); return
            case .right: self.volume = min(100, self.volume + 10); KeroFeedback.move(); return
            default: break
            }

        case .slot(let index):
            switch command
            {
            case .up: next = index > 0 ? .slot(index - 1) : nil
            case .down: next = index + 1 < stateCount ? .slot(index + 1) : .newSlot
            case .left: next = .action(.loadState)
            default: break
            }

        case .newSlot:
            switch command
            {
            case .up: next = stateCount > 0 ? .slot(stateCount - 1) : nil
            case .left: next = .action(.loadState)
            default: break
            }
        }

        if let next
        {
            self.menuFocus = next
            KeroFeedback.move()
        }
        else
        {
            KeroFeedback.bump()
        }
    }

    private func stepFilter(by delta: Int)
    {
        let all = KeroVideoFilter.allCases
        let current = KeroVideoFilter(rawValue: UserDefaults.standard.integer(forKey: "videoFilter")) ?? .sharp
        let index = all.firstIndex(of: current) ?? 0
        let next = all[(index + delta + all.count) % all.count]
        UserDefaults.standard.set(next.rawValue, forKey: "videoFilter")
        KeroFeedback.move()
    }
}

// MARK: - View -

struct KeroPauseMenu: View
{
    @Bindable var session: GameSession

    @AppStorage("videoFilter") private var filterRawValue = KeroVideoFilter.sharp.rawValue

    private var showsFocus: Bool { self.session.isControllerConnected || self.session.menuUsesFocus }

    var body: some View
    {
        GeometryReader { geometry in
            let isNarrow = geometry.size.width < 760
            let scale = isNarrow ? 1 : min(1.15, max(0.62, min(geometry.size.width / 1180, geometry.size.height / 830)))

            ZStack {
                Color(hex: 0x08090C, opacity: 0.72)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { self.session.closeMenu() }

                if isNarrow
                {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            self.mainColumn(scale: 1, fillsHeight: false)
                            self.slotsPanel(scale: 1, fillsHeight: false)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 28)
                    }
                    .scrollIndicators(.hidden)
                }
                else
                {
                    HStack(alignment: .top, spacing: 40 * scale) {
                        self.mainColumn(scale: scale, fillsHeight: true)
                        self.slotsPanel(scale: scale, fillsHeight: true)
                            .frame(width: 360 * scale)
                    }
                    .padding(.horizontal, 56 * scale)
                    .padding(.vertical, 40 * scale)
                    .padding(geometry.safeAreaInsets)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: Left

    private func mainColumn(scale: CGFloat, fillsHeight: Bool) -> some View
    {
        VStack(alignment: .leading, spacing: 22 * scale) {
            HStack(spacing: 12) {
                KeroPowerLED(color: KeroTheme.paused, size: 8)
                Text("PAUSED")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(KeroTheme.pausedText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(self.session.game.name)
                    .font(.system(size: 44 * scale, weight: .heavy))
                    .foregroundStyle(KeroTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text("\(self.session.game.system.name) · This session \(Self.minutes(self.session.sessionSeconds))")
                    .font(.system(size: 14))
                    .foregroundStyle(KeroTheme.secondaryText)
            }

            VStack(spacing: 12) {
                self.resumeButton(scale: scale)

                ForEach(0 ..< 3, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(KeroPauseAction.allCases.filter { $0.rawValue / 2 == row }, id: \.self) { action in
                            self.actionButton(action, scale: scale)
                        }
                    }
                }
            }
            .frame(maxWidth: 560)

            if fillsHeight { Spacer(minLength: 12) }

            VStack(alignment: .leading, spacing: 14 * scale) {
                self.settingRow("Screen", focus: .filter) {
                    self.filterPicker
                }
                self.settingRow("Fast forward", focus: .speed) {
                    Slider(value: self.$session.fastForwardSpeed, in: 2 ... 8, step: 1)
                        .tint(KeroTheme.link)
                        .accessibilityLabel("Fast-forward speed")
                        .accessibilityValue("\(Int(self.session.fastForwardSpeed)) times")
                    Text("\(Int(self.session.fastForwardSpeed))×")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                self.settingRow("Volume", focus: .volume) {
                    Slider(value: self.$session.volume, in: 0 ... 100, step: 5)
                        .tint(KeroTheme.link)
                        .accessibilityLabel("Volume")
                    Text("\(Int(self.session.volume))")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
    }

    private func resumeButton(scale: CGFloat) -> some View
    {
        Button {
            self.session.closeMenu()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                Text("Resume")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                if self.session.isControllerConnected
                {
                    Text("Menu")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x50545D))
                }
            }
            .foregroundStyle(KeroTheme.background)
            .padding(.horizontal, 22)
            .frame(height: 68 * max(0.8, scale))
            .background(KeroTheme.primaryText, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .keroFocusRing(self.showsFocus && self.session.menuFocus == .resume, shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(KeroPressStyle())
    }

    private func actionButton(_ action: KeroPauseAction, scale: CGFloat) -> some View
    {
        let isDisabled = action == .loadState && !self.session.hasSaveState
        let color = action == .quit ? KeroTheme.danger : KeroTheme.primaryText
        let title = action == .fastForward && self.session.isFastForwarding ? "Normal speed" : action.title

        return Button {
            self.session.perform(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 18 * max(0.8, scale))
            .frame(height: 60 * max(0.8, scale))
            .keroCard(cornerRadius: 18, fill: KeroTheme.surface, stroke: Color.white.opacity(0.09))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isDisabled ? 0.45 : 1)
            .keroFocusRing(self.showsFocus && self.session.menuFocus == .action(action), shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(KeroPressStyle())
        .disabled(isDisabled)
    }

    private func settingRow<Content: View>(_ title: String, focus: KeroPauseFocus, @ViewBuilder content: () -> Content) -> some View
    {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(KeroTheme.secondaryText)
                .frame(width: 92, alignment: .leading)
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .keroFocusRing(self.showsFocus && self.session.menuFocus == focus, shape: RoundedRectangle(cornerRadius: 14, style: .continuous), gap: 0, width: 2)
        .padding(.horizontal, -8)
    }

    private var filterPicker: some View
    {
        HStack(spacing: 4) {
            ForEach(KeroVideoFilter.allCases, id: \.rawValue) { filter in
                let isSelected = filter.rawValue == self.filterRawValue
                Button {
                    self.filterRawValue = filter.rawValue
                    KeroFeedback.tap()
                } label: {
                    Text(filter.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? KeroTheme.background : KeroTheme.mutedText)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(isSelected ? KeroTheme.primaryText : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(KeroTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(KeroTheme.stroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen filter")
    }

    // MARK: Right

    private func slotsPanel(scale: CGFloat, fillsHeight: Bool) -> some View
    {
        let states = self.session.menuStates

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Save states")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                if !states.isEmpty
                {
                    Text("Tap to load")
                        .font(.system(size: 12))
                        .foregroundStyle(KeroTheme.secondaryText)
                }
            }
            .foregroundStyle(KeroTheme.primaryText)

            if states.isEmpty
            {
                Text("No save states yet. Save one to pick up from this exact moment later.")
                    .font(.system(size: 13))
                    .foregroundStyle(KeroTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(states.enumerated()), id: \.element.id) { index, state in
                Button {
                    self.session.loadState(slot: state.slot)
                } label: {
                    HStack(spacing: 14) {
                        KeroSaveStateThumbnail(state: state, system: self.session.game.system, cornerRadius: 10)
                            .frame(width: 108 * max(0.8, scale), height: 72 * max(0.8, scale))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(KeroTheme.primaryText)
                            Text(state.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(KeroTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .keroCard(cornerRadius: 16, fill: Color.white.opacity(0.04),
                              stroke: index == 0 ? KeroTheme.link.opacity(0.55) : KeroTheme.stroke)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .keroFocusRing(self.showsFocus && self.session.menuFocus == .slot(index), shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(KeroPressStyle())
                .accessibilityLabel(Text("Load \(state.name), \(state.detail)"))
            }

            if fillsHeight { Spacer(minLength: 8) }

            Button {
                self.session.saveToNewSlot()
            } label: {
                Text("Save to a new slot")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KeroTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .keroFocusRing(self.showsFocus && self.session.menuFocus == .newSlot, shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(KeroPressStyle())
        }
        .padding(22)
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .keroCard(cornerRadius: 26, fill: KeroTheme.surface, stroke: KeroTheme.stroke)
    }

    private static func minutes(_ seconds: Double) -> String
    {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
