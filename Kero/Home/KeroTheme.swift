//
//  KeroTheme.swift
//  Kero
//
//  Visual language for the Kero home screen: a bright, glossy,
//  "Aero"-style look (sky gradients, glass, bubbles) designed from scratch.
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftUI

import KeroEngine

enum KeroTheme
{
    // MARK: Palette

    struct Palette
    {
        var skyTop: Color
        var skyMiddle: Color
        var skyBottom: Color
        var ribbon: Color
        var glassFill: Color
        var glassStroke: Color
        var text: Color
        var secondaryText: Color
        var focusGlow: Color
    }

    static let day = Palette(skyTop: Color(red: 0.02, green: 0.42, blue: 0.86),
                             skyMiddle: Color(red: 0.20, green: 0.68, blue: 0.96),
                             skyBottom: Color(red: 0.55, green: 0.86, blue: 1.00),
                             ribbon: .white,
                             glassFill: Color.white.opacity(0.22),
                             glassStroke: Color.white.opacity(0.55),
                             text: .white,
                             secondaryText: Color.white.opacity(0.82),
                             focusGlow: Color(red: 0.55, green: 1.0, blue: 0.98))

    static let night = Palette(skyTop: Color(red: 0.01, green: 0.05, blue: 0.16),
                               skyMiddle: Color(red: 0.02, green: 0.20, blue: 0.38),
                               skyBottom: Color(red: 0.04, green: 0.46, blue: 0.58),
                               ribbon: Color(red: 0.55, green: 0.95, blue: 1.0),
                               glassFill: Color.white.opacity(0.10),
                               glassStroke: Color.white.opacity(0.30),
                               text: .white,
                               secondaryText: Color.white.opacity(0.72),
                               focusGlow: Color(red: 0.40, green: 0.95, blue: 1.0))

    static func palette(for colorScheme: ColorScheme) -> Palette
    {
        return colorScheme == .dark ? self.night : self.day
    }

    // MARK: Systems

    static func tint(for system: KeroSystem) -> Color
    {
        switch system
        {
        case .gameBoyAdvance: return Color(red: 0.42, green: 0.32, blue: 0.94)
        case .gameBoyColor: return Color(red: 0.12, green: 0.72, blue: 0.48)
        case .gameBoy: return Color(red: 0.45, green: 0.55, blue: 0.20)
        case .nes: return Color(red: 0.88, green: 0.20, blue: 0.24)
        case .snes: return Color(red: 0.55, green: 0.38, blue: 0.86)
        case .genesis: return Color(red: 0.12, green: 0.30, blue: 0.80)
        }
    }

    // MARK: Type

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font
    {
        return .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Glass -

struct KeroGlass<S: Shape>: ViewModifier
{
    var shape: S
    var palette: KeroTheme.Palette

    func body(content: Content) -> some View
    {
        content
            .background(.ultraThinMaterial, in: self.shape)
            .background(self.palette.glassFill, in: self.shape)
            .overlay(
                self.shape.stroke(LinearGradient(colors: [self.palette.glassStroke, self.palette.glassStroke.opacity(0.1)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

extension View
{
    func keroGlass<S: Shape>(_ shape: S, palette: KeroTheme.Palette) -> some View
    {
        self.modifier(KeroGlass(shape: shape, palette: palette))
    }
}

// MARK: - Glossy capsule button style -

struct KeroGlossyButtonStyle: ButtonStyle
{
    var tint: Color
    var isFocused: Bool = false
    var palette: KeroTheme.Palette

    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            .font(KeroTheme.font(17, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Capsule().fill(LinearGradient(colors: [self.tint.opacity(0.95), self.tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))

                    // Top gloss
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.05)], startPoint: .top, endPoint: .center))
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                        .mask(VStack(spacing: 0) { Rectangle(); Color.clear })
                }
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
            .overlay(
                Capsule()
                    .stroke(self.palette.focusGlow, lineWidth: self.isFocused ? 3 : 0)
                    .shadow(color: self.palette.focusGlow, radius: self.isFocused ? 8 : 0)
                    .padding(-4)
            )
            .shadow(color: self.tint.opacity(0.45), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : (self.isFocused ? 1.06 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: self.isFocused)
    }
}
