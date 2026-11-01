//
//  KeroConsoleLayout.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Where everything goes on the game screen: the picture, its bezel and every control.
//  One source of truth for the console shell (SwiftUI), the game view and the touch controller (UIKit).
//  All frames are in full-screen points (safe areas ignored; insets are applied here).
//

import SwiftUI

import KeroEngine

struct KeroConsoleLayout: Equatable
{
    enum Style: Equatable
    {
        /// Game Boy–style body: screen on top, controls below.
        case portrait
        /// GBA-style body: screen in the middle, controls on either side, nothing overlapping.
        case landscape
        /// Full-screen picture with translucent controls on top.
        case overlay
        /// Picture only (a controller is connected).
        case screenOnly
    }

    var style: Style
    var size: CGSize

    var screen: CGRect = .zero
    var bezel: CGRect = .zero
    /// Strip under the screen for the power light and wordmark (portrait only).
    var label: CGRect = .zero
    var speaker: CGRect = .zero
    /// Portrait: the band across the middle where a foldable's hinge is. Nothing interactive goes here.
    var hinge: CGRect = .zero

    var menu: CGRect = .zero
    var dpad: CGRect = .zero
    var a: CGRect = .zero
    var b: CGRect = .zero
    var l: CGRect = .zero
    var r: CGRect = .zero
    var select: CGRect = .zero
    var start: CGRect = .zero

    var hasControls: Bool { self.style != .screenOnly }
    var hasShell: Bool { self.style == .portrait || self.style == .landscape }

    static func hasShoulders(_ system: KeroSystem) -> Bool
    {
        return system == .gameBoyAdvance || system == .snes
    }

    static func make(style: Style, size: CGSize, insets: EdgeInsets, aspect: CGFloat, system: KeroSystem) -> KeroConsoleLayout
    {
        var layout = KeroConsoleLayout(style: style, size: size)
        guard size.width > 100, size.height > 100, aspect > 0 else { return layout }

        let shoulders = self.hasShoulders(system)

        switch style
        {
        case .portrait: layout.layoutPortrait(insets: insets, aspect: aspect, shoulders: shoulders)
        case .landscape: layout.layoutLandscape(insets: insets, aspect: aspect, shoulders: shoulders)
        case .overlay: layout.layoutOverlay(insets: insets, aspect: aspect, shoulders: shoulders)
        case .screenOnly: layout.layoutScreenOnly(insets: insets, aspect: aspect)
        }

        return layout
    }
}

private extension KeroConsoleLayout
{
    static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat
    {
        return min(max(value, low), high)
    }

    static func fit(aspect: CGFloat, in rect: CGRect) -> CGRect
    {
        guard rect.width > 0, rect.height > 0 else { return .zero }

        var width = rect.width
        var height = width / aspect
        if height > rect.height
        {
            height = rect.height
            width = height * aspect
        }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    static func square(center: CGPoint, size: CGFloat) -> CGRect
    {
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    // MARK: Portrait

    /// Clamshell, like a GBA SP: screen in the top half, controls in the bottom half, and nothing
    /// interactive across the middle, where iPhone Duo's hinge is when the inner display is upright.
    mutating func layoutPortrait(insets: EdgeInsets, aspect: CGFloat, shoulders: Bool)
    {
        let width = self.size.width
        let height = self.size.height
        let margin = Self.clamp(width * 0.05, 14, 32)

        let hingeHeight = height * 0.08
        self.hinge = CGRect(x: 0, y: height / 2 - hingeHeight / 2, width: width, height: hingeHeight)

        // Top half: bezel with the picture and a label strip, centred in the space above the hinge.
        let top = max(insets.top, 10) + 4
        let topLimit = self.hinge.minY - 6
        let padding = Self.clamp(width * 0.035, 8, 18)
        let labelHeight: CGFloat = 26

        var screenWidth = width - margin * 2 - padding * 2
        var screenHeight = screenWidth / aspect
        let maxScreenHeight = topLimit - top - padding - labelHeight
        if screenHeight > maxScreenHeight
        {
            screenHeight = max(maxScreenHeight, 40)
            screenWidth = screenHeight * aspect
        }

        let bezelSize = CGSize(width: screenWidth + padding * 2, height: padding + screenHeight + labelHeight)
        let bezelY = top + max(0, (topLimit - top - bezelSize.height) / 2)
        self.bezel = CGRect(x: (width - bezelSize.width) / 2, y: bezelY, width: bezelSize.width, height: bezelSize.height)
        self.screen = CGRect(x: self.bezel.minX + padding, y: self.bezel.minY + padding, width: screenWidth, height: screenHeight)
        self.label = CGRect(x: self.screen.minX, y: self.screen.maxY, width: screenWidth, height: labelHeight)

        // Bottom half.
        let bottom = height - max(insets.bottom, 12) - 6
        let areaTop = self.hinge.maxY + 8

        let shoulderHeight: CGFloat = 42
        if shoulders
        {
            let shoulderWidth = Self.clamp(width * 0.27, 90, 160)
            self.l = CGRect(x: margin, y: areaTop, width: shoulderWidth, height: shoulderHeight)
            self.r = CGRect(x: width - margin - shoulderWidth, y: areaTop, width: shoulderWidth, height: shoulderHeight)
        }
        self.menu = Self.square(center: CGPoint(x: width / 2, y: areaTop + shoulderHeight / 2), size: 40)

        let bodyTop = areaTop + shoulderHeight + 10
        let pillSize = CGSize(width: 68, height: 28)
        let selectRowHeight = pillSize.height + 18
        let mainHeight = max(bottom - bodyTop - selectRowHeight, 80)

        let dpadSize = Self.clamp(min(width * 0.38, mainHeight * 0.86), 100, 210)
        let centerY = bodyTop + mainHeight / 2
        self.dpad = CGRect(x: margin + width * 0.02, y: centerY - dpadSize / 2, width: dpadSize, height: dpadSize)

        let faceSize = dpadSize * 0.42
        let aCenter = CGPoint(x: width - margin - width * 0.02 - faceSize / 2, y: centerY - faceSize * 0.38)
        let bCenter = CGPoint(x: aCenter.x - faceSize * 1.28, y: centerY + faceSize * 0.38)
        self.a = Self.square(center: aCenter, size: faceSize)
        self.b = Self.square(center: bCenter, size: faceSize)

        let pillY = min(bottom - pillSize.height, self.dpad.maxY + 16)
        self.select = CGRect(x: width / 2 - pillSize.width - 10, y: pillY, width: pillSize.width, height: pillSize.height)
        self.start = CGRect(x: width / 2 + 10, y: pillY, width: pillSize.width, height: pillSize.height)

        let speakerSize = CGSize(width: 64, height: 40)
        let speakerY = max(self.b.maxY + 16, pillY - 8)
        if speakerY + speakerSize.height <= bottom + 4
        {
            self.speaker = CGRect(x: width - margin - speakerSize.width, y: speakerY, width: speakerSize.width, height: speakerSize.height)
        }
    }

    // MARK: Landscape

    /// GBA-style: picture in the middle, controls in narrow columns either side. The columns are
    /// sized to the controls (not a fixed share of the screen) so the picture gets as much room as possible.
    /// L/R sit above the D-pad and face buttons, where thumbs reach; the menu button stays off the centre
    /// line (iPhone Duo's hinge runs down the middle of the inner display in landscape).
    mutating func layoutLandscape(insets: EdgeInsets, aspect: CGFloat, shoulders: Bool)
    {
        let width = self.size.width
        let height = self.size.height
        let margin = Self.clamp(height * 0.03, 10, 20)

        let left = insets.leading + margin
        let right = width - insets.trailing - margin
        let top = max(insets.top, margin)
        let bottom = height - max(insets.bottom, margin)

        let dpadSize = Self.clamp(height * 0.27, 110, 172)
        let faceSize = dpadSize * 0.44
        let columnWidth = max(dpadSize * 1.14, faceSize * 2.5)

        // Picture between the columns, as big as fits.
        let padding: CGFloat = 7
        let gap = margin * 0.6
        let center = CGRect(x: left + columnWidth + gap, y: top,
                            width: max(right - left - (columnWidth + gap) * 2, 100), height: bottom - top)
        self.screen = Self.fit(aspect: aspect, in: center.insetBy(dx: padding, dy: padding))
        self.bezel = self.screen.insetBy(dx: -padding, dy: -padding)

        let leftX = left + columnWidth / 2
        let rightX = right - columnWidth / 2
        let centerY = height * 0.58

        self.dpad = Self.square(center: CGPoint(x: leftX, y: centerY), size: dpadSize)
        self.a = Self.square(center: CGPoint(x: rightX + faceSize * 0.6, y: centerY - faceSize * 0.38), size: faceSize)
        self.b = Self.square(center: CGPoint(x: rightX - faceSize * 0.6, y: centerY + faceSize * 0.38), size: faceSize)

        // Shoulders: big, just above the D-pad / face buttons.
        let shoulderHeight = Self.clamp(height * 0.085, 42, 56)
        let shoulderY = max(top + 46, self.dpad.minY - dpadSize * 0.12 - shoulderHeight - 14)
        if shoulders
        {
            self.l = CGRect(x: left, y: shoulderY, width: columnWidth, height: shoulderHeight)
            self.r = CGRect(x: right - columnWidth, y: shoulderY, width: columnWidth, height: shoulderHeight)
        }

        let pillSize = CGSize(width: 66, height: 28)
        let pillY = bottom - pillSize.height
        self.select = CGRect(x: leftX - pillSize.width / 2, y: pillY, width: pillSize.width, height: pillSize.height)
        self.start = CGRect(x: rightX - pillSize.width / 2, y: pillY, width: pillSize.width, height: pillSize.height)

        // Menu: top of the right column.
        self.menu = Self.square(center: CGPoint(x: rightX, y: top + 20), size: 40)
    }

    // MARK: Overlay

    mutating func layoutOverlay(insets: EdgeInsets, aspect: CGFloat, shoulders: Bool)
    {
        let width = self.size.width
        let height = self.size.height
        let margin: CGFloat = 20

        self.screen = Self.fit(aspect: aspect, in: CGRect(origin: .zero, size: self.size))

        let left = insets.leading + margin
        let right = width - insets.trailing - margin
        let top = max(insets.top, 12)
        let bottom = height - max(insets.bottom, 16)

        if shoulders
        {
            self.l = CGRect(x: left, y: top, width: 100, height: 36)
            self.r = CGRect(x: right - 100, y: top, width: 100, height: 36)
        }

        let dpadSize = Self.clamp(height * 0.40, 110, 168)
        self.dpad = CGRect(x: left, y: bottom - 40 - dpadSize, width: dpadSize, height: dpadSize)

        let faceSize = dpadSize * 0.40
        let centerY = self.dpad.midY
        let aCenter = CGPoint(x: right - faceSize / 2, y: centerY - faceSize * 0.38)
        let bCenter = CGPoint(x: aCenter.x - faceSize * 1.22, y: centerY + faceSize * 0.38)
        self.a = Self.square(center: aCenter, size: faceSize)
        self.b = Self.square(center: bCenter, size: faceSize)

        let pillSize = CGSize(width: 64, height: 26)
        self.select = CGRect(x: self.dpad.midX - pillSize.width / 2, y: bottom - pillSize.height, width: pillSize.width, height: pillSize.height)
        self.start = CGRect(x: (aCenter.x + bCenter.x) / 2 - pillSize.width / 2, y: bottom - pillSize.height, width: pillSize.width, height: pillSize.height)

        self.menu = Self.square(center: CGPoint(x: width / 2, y: top + 20), size: 40)
    }

    // MARK: Screen only

    mutating func layoutScreenOnly(insets: EdgeInsets, aspect: CGFloat)
    {
        let safe = CGRect(x: insets.leading, y: insets.top,
                          width: self.size.width - insets.leading - insets.trailing,
                          height: self.size.height - insets.top - insets.bottom)
        self.screen = Self.fit(aspect: aspect, in: safe)
        self.menu = Self.square(center: CGPoint(x: self.size.width - insets.trailing - 32, y: max(insets.top, 12) + 20), size: 40)
    }
}
