//
//  KeroArtwork.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftUI
import UIKit

import KeroEngine

/// A game's cover: its artwork if it has one, otherwise a clean generated "cartridge label".
struct KeroGameCover: View
{
    let game: KeroGame
    var cornerRadius: CGFloat = 14
    /// Whether the generated cover prints the game's name (off where the name is shown underneath).
    var showsTitle = true
    /// Adds the system tag (and the name, when `showsTitle`) on top of real artwork too.
    var labelsArtwork = false

    var body: some View
    {
        KeroArtworkImage(url: self.game.artworkURL) {
            KeroCoverPlaceholder(system: self.game.system, name: self.game.name, seed: self.game.identifier, showsTitle: self.showsTitle)
        } decoration: {
            if self.labelsArtwork
            {
                KeroArtworkLabel(system: self.game.system, name: self.showsTitle ? self.game.name : nil)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
    }
}

/// System tag and title over real box art, on a soft scrim so they stay readable.
private struct KeroArtworkLabel: View
{
    var system: KeroSystem
    var name: String?

    var body: some View
    {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(self.name == nil ? 0 : 0.7)],
                               startPoint: .top, endPoint: .bottom)

                Text(self.system.shortName.uppercased())
                    .font(.system(size: max(8, size * 0.076), weight: .bold))
                    .tracking(size * 0.01)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, size * 0.076)
                    .padding(.top, size * 0.068)

                if let name = self.name
                {
                    Text(name)
                        .font(.system(size: max(10, size * 0.106), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(size * 0.076)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Generated cover for games without artwork: a two-tone gradient with the system and title in clean type.
struct KeroCoverPlaceholder: View
{
    var system: KeroSystem
    var name: String
    /// Picks one of a few gradients, so a shelf of games without covers isn't one flat colour.
    var seed: String? = nil
    var showsTitle = true

    var body: some View
    {
        let colors = KeroCoverPalette.colors(system: self.system, seed: self.seed)

        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [colors.top, colors.bottom], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))

                Text(self.system.shortName.uppercased())
                    .font(.system(size: max(8, size * 0.076), weight: .bold))
                    .tracking(size * 0.01)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.leading, size * 0.076)
                    .padding(.top, size * 0.068)

                if self.showsTitle
                {
                    Text(self.name)
                        .font(.system(size: max(10, size * 0.106), weight: .bold))
                        .foregroundStyle(KeroTheme.primaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(size * 0.076)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

enum KeroCoverPalette
{
    private static let pairs: [(UInt32, UInt32)] = [
        (0x3B3F8F, 0x101126), (0xB5462F, 0x5A1B12), (0x2F8A6E, 0x0F3A2F), (0x5B5F6B, 0x1E2026),
        (0x7A4FB0, 0x2A1745), (0x8A9A3A, 0x2F3812), (0xC48A2A, 0x4A2C08), (0x2F5FA6, 0x0E1F3D),
        (0xA6406B, 0x3D0F22), (0x3A8FA6, 0x0E2F3D), (0x6B6B2F, 0x26260E), (0x4F4FB0, 0x17173D),
    ]

    static func colors(system: KeroSystem, seed: String?) -> (top: Color, bottom: Color)
    {
        guard let seed else {
            let tint = KeroTheme.tint(for: system)
            return (tint.lighter(0.12), tint.darker(0.2))
        }

        // Stable across launches (unlike `hashValue`).
        var hash: UInt32 = 2166136261
        for byte in seed.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        let pair = self.pairs[Int(hash % UInt32(self.pairs.count))]
        return (Color(hex: pair.0), Color(hex: pair.1))
    }
}

// MARK: - Loading & caching -

final class KeroArtworkCache: @unchecked Sendable
{
    static let shared = KeroArtworkCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let colors = NSCache<NSURL, UIColor>()

    func image(for url: URL) -> UIImage?
    {
        return self.cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL)
    {
        self.cache.setObject(image, forKey: url as NSURL)
    }

    func cachedAverageColor(for url: URL) -> UIColor?
    {
        return self.colors.object(forKey: url as NSURL)
    }

    /// The cover's average colour, for the glow behind the home screen.
    func averageColor(for url: URL) async -> UIColor?
    {
        if let color = self.colors.object(forKey: url as NSURL) { return color }

        let color: UIColor? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data)?.cgImage else { return nil }

            var pixel = [UInt8](repeating: 0, count: 4)
            let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            guard drawn else { return nil }
            return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        }.value

        if let color { self.colors.setObject(color, forKey: url as NSURL) }
        return color
    }
}

struct KeroArtworkImage<Placeholder: View, Decoration: View>: View
{
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var decoration: () -> Decoration

    @State private var image: UIImage? = nil

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder, @ViewBuilder decoration: @escaping () -> Decoration)
    {
        self.url = url
        self.placeholder = placeholder
        self.decoration = decoration
    }

    var body: some View
    {
        // Color.clear takes exactly the proposed size; the image fills it and is clipped.
        Color.clear
            .overlay {
                if let image = self.image ?? self.url.flatMap({ KeroArtworkCache.shared.image(for: $0) })
                {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay { self.decoration() }
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

extension KeroArtworkImage where Decoration == EmptyView
{
    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder)
    {
        self.init(url: url, placeholder: placeholder, decoration: { EmptyView() })
    }
}
