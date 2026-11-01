//
//  KeroBubble.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  A glossy round "bubble" icon for games and built-in apps.
//

import SwiftUI

import KeroEngine

struct KeroBubble: View
{
    let tile: KeroTile
    let diameter: CGFloat
    let isFocused: Bool
    let isRunning: Bool
    let palette: KeroTheme.Palette

    var body: some View
    {
        VStack(spacing: self.diameter * 0.1) {
            self.sphere
                .frame(width: self.diameter, height: self.diameter)
                .scaleEffect(self.isFocused ? 1.13 : 1.0)
                .modifier(KeroBobbing(isActive: self.isFocused))

            Text(self.title)
                .font(KeroTheme.font(min(15, max(11, self.diameter * 0.15)), self.isFocused ? .bold : .semibold))
                .foregroundStyle(self.palette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: self.diameter * 1.38)
                .opacity(self.isFocused ? 1.0 : 0.92)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: self.isFocused)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

private extension KeroBubble
{
    var title: String {
        switch self.tile
        {
        case .app(let app): return app.title
        case .game(let game): return game.name
        }
    }

    var tint: Color {
        switch self.tile
        {
        case .app(let app): return app.tint
        case .game(let game): return KeroTheme.tint(for: game.system)
        }
    }

    var accessibilityText: String {
        switch self.tile
        {
        case .app(let app): return app.title
        case .game(let game): return "\(game.name), \(game.system.name)"
        }
    }

    var sphere: some View {
        ZStack {
            self.sphereContent
                .clipShape(Circle())

            self.sphereFinish

            self.badges
        }
        .compositingGroup()
        .shadow(color: .black.opacity(self.isFocused ? 0.32 : 0.22), radius: self.isFocused ? 12 : 7, y: self.isFocused ? 9 : 5)
    }

    @ViewBuilder
    var sphereContent: some View {
        switch self.tile
        {
        case .app(let app):
            ZStack {
                Circle().fill(LinearGradient(colors: [app.tint.lighter(0.25), app.tint, app.tint.darker(0.2)], startPoint: .top, endPoint: .bottom))

                Image(systemName: app.symbolName)
                    .font(.system(size: self.diameter * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }

        case .game(let game):
            KeroArtworkImage(url: game.artworkURL) {
                KeroArtworkPlaceholder(system: game.system, name: game.name, showsSystemName: false)
            }
        }
    }

    /// Shading, gloss, rim and focus glow layered over the content.
    var sphereFinish: some View {
        let d = self.diameter
        let shade = RadialGradient(colors: [Color.clear, self.tint.darker(0.3).opacity(0.45)], center: .center, startRadius: d * 0.32, endRadius: d * 0.52)
        let gloss = LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
        let rim = LinearGradient(colors: [Color.white, Color.white.opacity(0.55)], startPoint: .top, endPoint: .bottom)

        return ZStack {
            // Inner shading toward the rim gives the sphere some volume.
            Circle().fill(shade)

            // Glossy top highlight.
            Ellipse()
                .fill(gloss)
                .frame(width: d * 0.74, height: d * 0.42)
                .offset(y: -d * 0.23)
                .blendMode(.screen)

            // Small bottom reflection.
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: d * 0.4, height: d * 0.08)
                .offset(y: d * 0.37)
                .blur(radius: 1.5)

            Circle()
                .strokeBorder(rim, lineWidth: max(2, d * 0.035))

            // Focus glow
            Circle()
                .stroke(self.palette.focusGlow, lineWidth: 3)
                .padding(-5)
                .shadow(color: self.palette.focusGlow.opacity(0.9), radius: 10)
                .opacity(self.isFocused ? 1 : 0)
        }
    }

    @ViewBuilder
    var badges: some View {
        let d = self.diameter

        if case .game(let game) = self.tile
        {
            // System badge
            Text(game.system.shortName)
                .font(KeroTheme.font(max(8, d * 0.11), .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, d * 0.06)
                .padding(.vertical, d * 0.025)
                .background(Capsule().fill(KeroTheme.tint(for: game.system)))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1.2))
                .offset(x: d * 0.32, y: d * 0.36)

            if game.isFavorite
            {
                Image(systemName: "star.fill")
                    .font(.system(size: max(9, d * 0.14), weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.2))
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                    .offset(x: d * 0.36, y: -d * 0.34)
            }

            if self.isRunning
            {
                KeroRunningBadge(size: max(16, d * 0.24))
                    .offset(x: -d * 0.36, y: -d * 0.34)
            }
        }
    }
}

// MARK: - Supporting Views -

struct KeroRunningBadge: View
{
    var size: CGFloat

    var body: some View
    {
        Image(systemName: "play.fill")
            .font(.system(size: self.size * 0.45, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: self.size, height: self.size)
            .background(Circle().fill(Color(red: 0.15, green: 0.78, blue: 0.35)))
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .phaseAnimator([false, true]) { content, phase in
                content.scaleEffect(phase ? 1.08 : 0.94)
            } animation: { _ in .easeInOut(duration: 0.9) }
    }
}

/// Gentle floating motion for the focused bubble.
struct KeroBobbing: ViewModifier
{
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View
    {
        if self.isActive && !self.reduceMotion
        {
            content.phaseAnimator([false, true]) { content, phase in
                content.offset(y: phase ? -3 : 2)
            } animation: { _ in .easeInOut(duration: 1.3) }
        }
        else
        {
            content
        }
    }
}

struct KeroArtworkPlaceholder: View
{
    var system: KeroSystem
    var name: String
    /// Bubbles already carry a system badge, so they hide the name; the big LiveArea card shows it.
    var showsSystemName: Bool = true

    var body: some View
    {
        let tint = KeroTheme.tint(for: self.system)

        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                LinearGradient(colors: [tint.lighter(0.3), tint, tint.darker(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(spacing: size * 0.02) {
                    Text(String(self.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))

                    if self.showsSystemName
                    {
                        Text(self.system.shortName)
                            .font(.system(size: size * 0.11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Artwork -

final class KeroArtworkCache
{
    static let shared = KeroArtworkCache()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage?
    {
        return self.cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL)
    {
        self.cache.setObject(image, forKey: url as NSURL)
    }
}

struct KeroArtworkImage<Placeholder: View>: View
{
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage? = nil

    var body: some View
    {
        // Color.clear takes exactly the proposed size; the image fills it and is clipped,
        // so artwork of any aspect ratio never changes the layout.
        Color.clear
            .overlay {
                if let image = self.image ?? self.url.flatMap({ KeroArtworkCache.shared.image(for: $0) })
                {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                else
                {
                    self.placeholder()
                }
            }
            .clipped()
            .task(id: self.url) {
                await self.load()
            }
    }

    private func load() async
    {
        guard let url = self.url else {
            self.image = nil
            return
        }

        if let cached = KeroArtworkCache.shared.image(for: url)
        {
            self.image = cached
            return
        }

        do
        {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }

            KeroArtworkCache.shared.insert(image, for: url)
            self.image = image
        }
        catch
        {
            // Keep the placeholder; artwork is optional.
        }
    }
}

// MARK: - Color helpers -

extension Color
{
    func lighter(_ amount: CGFloat) -> Color
    {
        return self.adjusted(by: abs(amount))
    }

    func darker(_ amount: CGFloat) -> Color
    {
        return self.adjusted(by: -abs(amount))
    }

    private func adjusted(by amount: CGFloat) -> Color
    {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }

        let newBrightness = min(1, max(0, brightness + amount))
        let newSaturation = amount > 0 ? max(0, saturation - amount * 0.5) : saturation
        return Color(hue: Double(hue), saturation: Double(newSaturation), brightness: Double(newBrightness), opacity: Double(alpha))
    }
}
