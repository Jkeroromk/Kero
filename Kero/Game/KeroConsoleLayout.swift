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

    mutating func layoutPortrait(insets: EdgeInsets, aspect: CGFloat, shoulders: Bool)
    {
        let width = self.size.width
        let height = self.size.height
        let margin = Self.clamp(width * 0.05, 14, 32)

        // Bezel and screen. The picture uses the full width unless that would leave too little room for controls.
        let top = max(insets.top, 10) + 6
        let padding = Self.clamp(width * 0.035, 8, 18)
        let labelHeight: CGFloat = 26

        var screenWidth = width - margin * 2 - padding * 2
        var screenHeight = screenWidth / aspect
        let maxScreenHeight = height * 0.46
        if screenHeight > maxScreenHeight
        {
            screenHeight = maxScreenHeight
            screenWidth = screenHeight * aspect
        }

        let bezelWidth = screenWidth + padding * 2
        self.bezel = CGRect(x: (width - bezelWidth) / 2, y: top, width: bezelWidth, height: padding + screenHeight + labelHeight)
        self.screen = CGRect(x: self.bezel.minX + padding, y: self.bezel.minY + padding, width: screenWidth, height: screenHeight)
        self.label = CGRect(x: self.screen.minX, y: self.screen.maxY, width: screenWidth, height: labelHeight)

        // Controls.
        let bottom = height - max(insets.bottom, 12) - 6
        let areaTop = self.bezel.maxY + Self.clamp(height * 0.022, 10, 26)

        let shoulderHeight: CGFloat = 38
        let rowCenterY = areaTop + shoulderHeight / 2
        if shoulders
        {
            let shoulderWidth = Self.clamp(width * 0.26, 84, 150)
            self.l = CGRect(x: margin, y: areaTop, width: shoulderWidth, height: shoulderHeight)
            self.r = CGRect(x: width - margin - shoulderWidth, y: areaTop, width: shoulderWidth, height: shoulderHeight)
        }
        self.menu = Self.square(center: CGPoint(x: width / 2, y: rowCenterY), size: 38)

        let bodyTop = areaTop + shoulderHeight + 8
        let pillSize = CGSize(width: 66, height: 26)
        let selectRowHeight = pillSize.height + 18
        let mainHeight = max(bottom - bodyTop - selectRowHeight, 80)

        let dpadSize = max(Self.clamp(min(width * 0.38, mainHeight * 0.84), 100, 210), 0)
        let centerY = bodyTop + mainHeight / 2
        self.dpad = CGRect(x: margin + width * 0.02, y: centerY - dpadSize / 2, width: dpadSize, height: dpadSize)

        let faceSize = dpadSize * 0.42
        let aCenter = CGPoint(x: width - margin - width * 0.02 - faceSize / 2, y: centerY - faceSize * 0.38)
        let bCenter = CGPoint(x: aCenter.x - faceSize * 1.28, y: centerY + faceSize * 0.38)
        self.a = Self.square(center: aCenter, size: faceSize)
        self.b = Self.square(center: bCenter, size: faceSize)

        let pillY = min(bottom - pillSize.height, self.dpad.maxY + 18)
        self.select = CGRect(x: width / 2 - pillSize.width - 10, y: pillY, width: pillSize.width, height: pillSize.height)
        self.start = CGRect(x: width / 2 + 10, y: pillY, width: pillSize.width, height: pillSize.height)

        // Speaker grille in the bottom-right corner, if there's room under the face buttons.
        let speakerSize = CGSize(width: 64, height: 40)
        let speakerY = max(self.b.maxY + 16, pillY - 8)
        if speakerY + speakerSize.height <= bottom + 4
        {
            self.speaker = CGRect(x: width - margin - speakerSize.width, y: speakerY, width: speakerSize.width, height: speakerSize.height)
        }
    }

    // MARK: Landscape

    mutating func layoutLandscape(insets: EdgeInsets, aspect: CGFloat, shoulders: Bool)
    {
        let width = self.size.width
        let height = self.size.height
        let margin = Self.clamp(height * 0.04, 10, 24)

        let left = insets.leading + margin
        let right = width - insets.trailing - margin
        let top = max(insets.top, margin)
        let bottom = height - max(insets.bottom, margin)

        let columnWidth = Self.clamp(height * 0.34, 140, 230)
        let padding: CGFloat = 10

        // Picture between the two control columns.
        let center = CGRect(x: left + columnWidth, y: top, width: max(right - left - columnWidth * 2, 100), height: bottom - top)
        self.screen = Self.fit(aspect: aspect, in: center.insetBy(dx: padding, dy: padding))
        self.bezel = self.screen.insetBy(dx: -padding, dy: -padding)

        let shoulderSize = CGSize(width: min(columnWidth, 130), height: 38)
        if shoulders
        {
            self.l = CGRect(x: left, y: top, width: shoulderSize.width, height: shoulderSize.height)
            self.r = CGRect(x: right - shoulderSize.width, y: top, width: shoulderSize.width, height: shoulderSize.height)
        }

        let dpadSize = Self.clamp(min(columnWidth - 8, height * 0.42), 100, 190)
        let leftX = left + columnWidth / 2
        let rightX = right - columnWidth / 2
        let centerY = height * 0.55

        self.dpad = Self.square(center: CGPoint(x: leftX, y: centerY), size: dpadSize)

        let faceSize = dpadSize * 0.42
        self.a = Self.square(center: CGPoint(x: rightX + faceSize * 0.64, y: centerY - faceSize * 0.38), size: faceSize)
        self.b = Self.square(center: CGPoint(x: rightX - faceSize * 0.64, y: centerY + faceSize * 0.38), size: faceSize)

        let pillSize = CGSize(width: 64, height: 26)
        let pillY = bottom - pillSize.height
        self.select = CGRect(x: leftX - pillSize.width / 2, y: pillY, width: pillSize.width, height: pillSize.height)
        self.start = CGRect(x: rightX - pillSize.width / 2, y: pillY, width: pillSize.width, height: pillSize.height)

        // Home button: above or below the bezel if there's room, otherwise in the right column.
        if self.bezel.minY - top >= 44
        {
            self.menu = Self.square(center: CGPoint(x: width / 2, y: (top + self.bezel.minY) / 2), size: 38)
        }
        else if bottom - self.bezel.maxY >= 44
        {
            self.menu = Self.square(center: CGPoint(x: width / 2, y: (self.bezel.maxY + bottom) / 2), size: 38)
        }
        else
        {
            let y = shoulders ? self.r.maxY + 30 : top + 19
            self.menu = Self.square(center: CGPoint(x: rightX, y: y), size: 38)
        }
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
