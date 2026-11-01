//
//  KeroLid.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  iPhone Duo: folding the phone closes the "lid". The outer display shows Kero's closed
//  clamshell and the game pauses; unfolding opens it again and the game carries on.
//

import Observation
import SwiftUI

// MARK: - Fold detection -

/// Works out whether the app is on the (smaller) outer display: the window shrinks a lot when the
/// phone folds and grows back when it opens. The largest size seen is remembered across launches.
@MainActor
@Observable
final class KeroFoldMonitor
{
    private(set) var isFolded = false

    @ObservationIgnored private let largestAreaKey = "KeroLargestDisplayArea"

    func update(size: CGSize)
    {
        let area = size.width * size.height
        guard area > 0 else { return }

        var largest = UserDefaults.standard.double(forKey: self.largestAreaKey)
        if area > largest
        {
            largest = area
            UserDefaults.standard.set(largest, forKey: self.largestAreaKey)
        }

        // Rotation doesn't change the area; moving to the outer display shrinks it well below 80%.
        let folded = area < largest * 0.8
        if folded != self.isFolded
        {
            withAnimation(.easeInOut(duration: 0.35)) {
                self.isFolded = folded
            }
        }
    }
}

// MARK: - Lid colours -

enum KeroLidColor: String, CaseIterable, Identifiable
{
    case graphite
    case silver
    case indigo
    case coral
    case mint

    var id: String { self.rawValue }

    var name: String {
        switch self
        {
        case .graphite: return "Graphite"
        case .silver: return "Silver"
        case .indigo: return "Indigo"
        case .coral: return "Coral"
        case .mint: return "Mint"
        }
    }

    var top: Color {
        switch self
        {
        case .graphite: return Color(white: 0.24)
        case .silver: return Color(white: 0.84)
        case .indigo: return Color(red: 0.30, green: 0.32, blue: 0.62)
        case .coral: return Color(red: 0.93, green: 0.50, blue: 0.44)
        case .mint: return Color(red: 0.55, green: 0.82, blue: 0.72)
        }
    }

    var bottom: Color {
        switch self
        {
        case .graphite: return Color(white: 0.11)
        case .silver: return Color(white: 0.62)
        case .indigo: return Color(red: 0.16, green: 0.17, blue: 0.40)
        case .coral: return Color(red: 0.72, green: 0.31, blue: 0.28)
        case .mint: return Color(red: 0.33, green: 0.60, blue: 0.51)
        }
    }

    /// Light lids get dark engraving, dark lids get light engraving.
    var isLight: Bool { self == .silver || self == .mint }
}

// MARK: - Lid -

struct KeroLidView: View
{
    var color: KeroLidColor
    /// The game that's paused under the lid, if any.
    var gameName: String?

    @State private var isBreathing = false

    var body: some View
    {
        GeometryReader { geometry in
            let size = geometry.size
            let isPortrait = size.height >= size.width
            let shortSide = min(size.width, size.height)
            let engraving = self.color.isLight ? Color.black : Color.white

            ZStack {
                // Shell
                LinearGradient(colors: [self.color.top, self.color.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)

                KeroBrushedTexture(isLight: self.color.isLight)

                // Soft sheen across the lid.
                LinearGradient(colors: [.white.opacity(0.16), .clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom)

                // Raised panel with a bevelled edge.
                RoundedRectangle(cornerRadius: shortSide * 0.07, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.28)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
                    .padding(EdgeInsets(top: isPortrait ? shortSide * 0.13 : shortSide * 0.06,
                                        leading: isPortrait ? shortSide * 0.06 : shortSide * 0.13,
                                        bottom: shortSide * 0.06,
                                        trailing: shortSide * 0.06))

                KeroHinge(isPortrait: isPortrait, color: self.color, shortSide: shortSide)

                // Emblem: an engraved ring with the wordmark.
                VStack(spacing: shortSide * 0.05) {
                    ZStack {
                        Circle()
                            .strokeBorder(engraving.opacity(0.22), lineWidth: shortSide * 0.008)
                        Circle()
                            .strokeBorder(engraving.opacity(0.10), lineWidth: shortSide * 0.004)
                            .padding(shortSide * 0.03)

                        Text("KERO")
                            .font(.system(size: shortSide * 0.085, weight: .heavy))
                            .tracking(shortSide * 0.02)
                            .foregroundStyle(engraving.opacity(0.55))
                            .shadow(color: (self.color.isLight ? Color.white : Color.black).opacity(0.5), radius: 0, y: 1)
                    }
                    .frame(width: shortSide * 0.46, height: shortSide * 0.46)

                    Text("OPEN TO PLAY")
                        .font(.system(size: max(10, shortSide * 0.028), weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(engraving.opacity(0.35))
                }

                // Sleep light and what's paused.
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(self.gameName == nil ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .shadow(color: (self.gameName == nil ? Color.green : Color.orange).opacity(0.9), radius: self.isBreathing ? 5 : 1)
                            .opacity(self.isBreathing ? 1 : 0.35)

                        if let gameName = self.gameName
                        {
                            Text("Paused · \(gameName)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(engraving.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, shortSide * 0.11)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                self.isBreathing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(self.gameName.map { "Kero is closed. \($0) is paused. Unfold your iPhone to keep playing." } ?? "Kero is closed. Unfold your iPhone to play."))
    }
}

/// Fine brushed-metal lines, drawn once.
private struct KeroBrushedTexture: View
{
    var isLight: Bool

    var body: some View
    {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func random() -> Double
            {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                return Double(seed % 1000) / 1000
            }

            var y: CGFloat = 0
            while y < size.height
            {
                let alpha = 0.015 + random() * 0.035
                let color: Color = (random() > 0.5) ? .white : .black
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color.opacity(alpha)))
                y += 2
            }
        }
        .blendMode(self.isLight ? .multiply : .overlay)
        .allowsHitTesting(false)
    }
}

/// Hinge along the top (portrait) or left edge (landscape): two barrels with a gap between.
private struct KeroHinge: View
{
    var isPortrait: Bool
    var color: KeroLidColor
    var shortSide: CGFloat

    var body: some View
    {
        GeometryReader { geometry in
            let thickness = self.shortSide * 0.075
            let length = (self.isPortrait ? geometry.size.width : geometry.size.height) * 0.28
            let barrel = Capsule()
                .fill(LinearGradient(colors: [self.color.bottom.opacity(0.9), self.color.top, self.color.bottom],
                                     startPoint: self.isPortrait ? .top : .leading,
                                     endPoint: self.isPortrait ? .bottom : .trailing))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 3, x: self.isPortrait ? 0 : 2, y: self.isPortrait ? 2 : 0)

            if self.isPortrait
            {
                HStack {
                    barrel.frame(width: length, height: thickness)
                    Spacer()
                    barrel.frame(width: length, height: thickness)
                }
                .padding(.horizontal, self.shortSide * 0.08)
                .padding(.top, self.shortSide * 0.035)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            else
            {
                VStack {
                    barrel.frame(width: thickness, height: length)
                    Spacer()
                    barrel.frame(width: thickness, height: length)
                }
                .padding(.vertical, self.shortSide * 0.08)
                .padding(.leading, self.shortSide * 0.035)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
