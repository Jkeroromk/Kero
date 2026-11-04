//
//  KeroTheme.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Graphite console look: a near-black ground, quiet white-on-glass surfaces, one white pill for
//  the main action, and colour only where it means something (power light, paused, favourite).
//

import SwiftUI
import UIKit

import KeroEngine

enum KeroTheme
{
    // MARK: Colors

    /// #0b0c10
    static let background = Color(hex: 0x0B0C10)
    static let surface = Color.white.opacity(0.06)
    static let surfaceStrong = Color.white.opacity(0.08)
    static let surfaceHighlight = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.12)
    static let primaryText = Color(hex: 0xF4F5F7)
    static let secondaryText = Color(hex: 0xA3A7B0)
    static let tertiaryText = Color(hex: 0x8F939C)
    /// Top bar clock and battery.
    static let statusText = Color(hex: 0xB9BCC4)
    /// Unselected rail and chip text.
    static let mutedText = Color(hex: 0xD5D8DE)
    static let link = Color(hex: 0x9CC4FF)
    static let powerLED = Color(hex: 0x4CF08A)
    static let recognised = Color(hex: 0x7FF5AE)
    static let paused = Color(hex: 0xFFB547)
    static let pausedText = Color(hex: 0xFFCF85)
    static let favorite = Color(hex: 0xFFD36B)
    static let danger = Color(hex: 0xFF9D8F)
    static let focus = Color(hex: 0xF4F5F7)
    static let accent = Color(hex: 0x9CC4FF)

    /// Small square next to each system in the library.
    static func dot(for system: KeroSystem) -> Color
    {
        switch system
        {
        case .nintendoDS: return Color(hex: 0x7F93AD)
        case .gameBoyAdvance: return Color(hex: 0x8A83D6)
        case .gameBoyColor: return Color(hex: 0x4FB3A6)
        case .gameBoy: return Color(hex: 0x9AA86A)
        case .nes: return Color(hex: 0xC46A6A)
        case .snes: return Color(hex: 0x9A86C4)
        case .genesis: return Color(hex: 0x5F86C4)
        }
    }

    /// Deep per-system colour for the glow behind the home screen when a game has no cover.
    static func tint(for system: KeroSystem) -> Color
    {
        switch system
        {
        case .gameBoyAdvance: return Color(hex: 0x2C2F73)
        case .gameBoyColor: return Color(hex: 0x1F4A45)
        case .gameBoy: return Color(hex: 0x3A4426)
        case .nes: return Color(hex: 0x5A2A3C)
        case .snes: return Color(hex: 0x3D3366)
        case .genesis: return Color(hex: 0x23345E)
        case .nintendoDS: return Color(hex: 0x2B3A55)
        }
    }

    // MARK: Type (system font; weights match the design's Inter / Inter Tight)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    // MARK: Motion

    static let focusSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

extension Color
{
    init(hex: UInt32, opacity: Double = 1)
    {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Building blocks -

/// The green (or amber) power light next to the wordmark.
struct KeroPowerLED: View
{
    var color: Color = KeroTheme.powerLED
    var size: CGFloat = 8

    var body: some View
    {
        Circle()
            .fill(self.color)
            .frame(width: self.size, height: self.size)
            .shadow(color: self.color.opacity(0.8), radius: self.size * 0.6)
            .accessibilityHidden(true)
    }
}

struct KeroWordmark: View
{
    var size: CGFloat = 15
    var ledSize: CGFloat = 8

    var body: some View
    {
        HStack(spacing: self.size * 0.8) {
            KeroPowerLED(size: self.ledSize)
            Text("KERO")
                .font(.system(size: self.size, weight: .heavy))
                .tracking(self.size * 0.28)
                .foregroundStyle(KeroTheme.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Kero"))
    }
}

/// White pill for the one main action on a screen.
struct KeroPrimaryPill: View
{
    var title: String
    var symbol: String? = "play.fill"
    var height: CGFloat = 52
    var fontSize: CGFloat = 17
    var horizontalPadding: CGFloat = 28

    var body: some View
    {
        HStack(spacing: self.fontSize * 0.6) {
            if let symbol = self.symbol
            {
                Image(systemName: symbol)
                    .font(.system(size: self.fontSize * 0.85, weight: .bold))
            }
            Text(self.title)
                .font(.system(size: self.fontSize, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(KeroTheme.background)
        .padding(.horizontal, self.horizontalPadding)
        .frame(height: self.height)
        .background(KeroTheme.primaryText, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Glass pill with a label, for secondary actions.
struct KeroGlassPill: View
{
    var title: String
    var symbol: String? = nil
    var height: CGFloat = 44
    var fontSize: CGFloat = 14
    var horizontalPadding: CGFloat = 16
    var isDisabled = false

    var body: some View
    {
        HStack(spacing: 8) {
            if let symbol = self.symbol
            {
                Image(systemName: symbol)
                    .font(.system(size: self.fontSize * 1.1, weight: .semibold))
            }
            Text(self.title)
                .font(.system(size: self.fontSize, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(KeroTheme.primaryText.opacity(self.isDisabled ? 0.4 : 1))
        .padding(.horizontal, self.horizontalPadding)
        .frame(height: self.height)
        .background(KeroTheme.surfaceStrong, in: Capsule())
        .overlay(Capsule().strokeBorder(KeroTheme.strokeStrong, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Round glass button with one symbol.
struct KeroCircleIcon: View
{
    var symbol: String
    var size: CGFloat = 52
    var tint: Color = KeroTheme.primaryText

    var body: some View
    {
        Image(systemName: self.symbol)
            .font(.system(size: self.size * 0.36, weight: .semibold))
            .foregroundStyle(self.tint)
            .frame(width: self.size, height: self.size)
            .background(KeroTheme.surfaceStrong, in: Circle())
            .overlay(Circle().strokeBorder(KeroTheme.strokeStrong, lineWidth: 1))
            .contentShape(Circle())
    }
}

/// Small rounded label: system, region, languages…
struct KeroChip: View
{
    var text: String
    var foreground: Color = KeroTheme.mutedText
    var background: Color = Color.white.opacity(0.08)
    var fontSize: CGFloat = 12

    var body: some View
    {
        Text(self.text)
            .font(.system(size: self.fontSize, weight: .semibold))
            .foregroundStyle(self.foreground)
            .lineLimit(1)
            .padding(.horizontal, self.fontSize * 0.83)
            .padding(.vertical, self.fontSize * 0.33)
            .background(self.background, in: Capsule())
    }
}

/// "A Resume" style controller hint.
struct KeroButtonHint: View
{
    var button: String
    var title: String
    var size: CGFloat = 22

    var body: some View
    {
        HStack(spacing: 7) {
            Text(self.button)
                .font(.system(size: self.size * 0.5, weight: .heavy))
                .foregroundStyle(KeroTheme.background)
                .frame(width: self.size, height: self.size)
                .background(KeroTheme.primaryText, in: Circle())
            Text(self.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(KeroTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View
{
    /// White focus ring with a dark gap, as on the console: shown while `isFocused`.
    func keroFocusRing<S: InsettableShape>(_ isFocused: Bool, shape: S, gap: CGFloat = 3, width: CGFloat = 3) -> some View
    {
        self.overlay(
            shape
                .inset(by: -(gap + width / 2))
                .stroke(KeroTheme.focus, lineWidth: width)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        )
        .animation(KeroTheme.focusSpring, value: isFocused)
    }

    /// Glass card: white at 4–6 % with a hairline border.
    func keroCard(cornerRadius: CGFloat, fill: Color = Color.white.opacity(0.05), stroke: Color = KeroTheme.stroke) -> some View
    {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(stroke, lineWidth: 1))
    }
}

struct KeroPressStyle: ButtonStyle
{
    func makeBody(configuration: Configuration) -> some View
    {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Text -

enum KeroFormat
{
    /// "12 h 40 m", "38 m", "< 1 m".
    static func playTime(_ seconds: Double) -> String
    {
        let minutes = Int(seconds / 60)
        if seconds <= 0 { return "0 m" }
        if minutes < 1 { return "< 1 m" }
        if minutes < 60 { return "\(minutes) m" }
        return String(format: "%d h %02d m", minutes / 60, minutes % 60)
    }

    /// "Just now", "12 min ago", "2 h ago", "Yesterday", "3 days ago", "Last week", "Oct 28".
    static func when(_ date: Date, now: Date = Date()) -> String
    {
        let calendar = Calendar.current
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600)) h ago" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days) days ago" }
        if days < 14 { return "Last week" }
        return self.day(date, now: now)
    }

    /// "Oct 28", or "Oct 28, 2025" in another year.
    static func day(_ date: Date, now: Date = Date()) -> String
    {
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Today 9:42", "Yesterday 21:10", "Oct 31 · 20:14".
    static func stamp(_ date: Date, now: Date = Date()) -> String
    {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return "\(self.day(date, now: now)) · \(time)"
    }

    /// "English · French · German", at most three, "+2" for the rest.
    static func languages(_ codes: [String]) -> String?
    {
        let names = codes.compactMap { Locale.current.localizedString(forLanguageCode: $0) }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(3).joined(separator: " · ")
        return names.count > 3 ? shown + " +\(names.count - 3)" : shown
    }
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
