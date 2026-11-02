//
//  KeroTheme.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Console-style visual language: dark, quiet surfaces; the game art provides the color.
//

import SwiftUI
import UIKit

import KeroEngine

enum KeroTheme
{
    // MARK: Colors

    static let background = Color(red: 0.035, green: 0.04, blue: 0.055)
    static let surface = Color.white.opacity(0.06)
    static let surfaceHighlight = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)
    static let focus = Color.white
    static let accent = Color(red: 0.24, green: 0.56, blue: 1.0)

    /// Muted per-system tint, used for placeholder art and small labels.
    static func tint(for system: KeroSystem) -> Color
    {
        switch system
        {
        case .gameBoyAdvance: return Color(red: 0.36, green: 0.33, blue: 0.62)
        case .gameBoyColor: return Color(red: 0.20, green: 0.45, blue: 0.42)
        case .gameBoy: return Color(red: 0.38, green: 0.42, blue: 0.30)
        case .nes: return Color(red: 0.52, green: 0.22, blue: 0.24)
        case .snes: return Color(red: 0.40, green: 0.36, blue: 0.52)
        case .genesis: return Color(red: 0.18, green: 0.26, blue: 0.48)
        case .nintendoDS: return Color(red: 0.30, green: 0.36, blue: 0.44)
        }
    }

    // MARK: Type

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    // MARK: Motion

    static let focusSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

// MARK: - Feedback -

enum KeroFeedback
{
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    static func move() { self.selection.selectionChanged() }
    static func select() { self.light.impactOccurred() }
    static func tap() { self.soft.impactOccurred() }
    static func bump() { self.rigid.impactOccurred(intensity: 0.4) }
}

// MARK: - Color helpers -

extension Color
{
    func lighter(_ amount: CGFloat) -> Color { self.adjusted(by: abs(amount)) }
    func darker(_ amount: CGFloat) -> Color { self.adjusted(by: -abs(amount)) }

    private func adjusted(by amount: CGFloat) -> Color
    {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }

        let newBrightness = min(1, max(0, brightness + amount))
        let newSaturation = amount > 0 ? max(0, saturation - amount * 0.5) : saturation
        return Color(hue: Double(hue), saturation: Double(newSaturation), brightness: Double(newBrightness), opacity: Double(alpha))
    }
}
