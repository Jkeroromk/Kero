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

    var body: some View
    {
        KeroArtworkImage(url: self.game.artworkURL) {
            KeroCoverPlaceholder(system: self.game.system, name: self.game.name)
        }
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
    }
}

/// Generated cover for games without artwork: muted system color, title in clean type.
struct KeroCoverPlaceholder: View
{
    var system: KeroSystem
    var name: String

    var body: some View
    {
        let tint = KeroTheme.tint(for: self.system)

        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [tint.lighter(0.08), tint.darker(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)

                // Subtle diagonal sheen so it doesn't look flat.
                LinearGradient(colors: [Color.white.opacity(0.10), Color.clear], startPoint: .top, endPoint: .center)

                VStack(alignment: .leading, spacing: size * 0.03) {
                    Text(self.system.shortName.uppercased())
                        .font(.system(size: max(8, size * 0.075), weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.65))

                    Text(self.name)
                        .font(.system(size: max(11, size * 0.115), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                .padding(size * 0.09)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Loading & caching -

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
        // Color.clear takes exactly the proposed size; the image fills it and is clipped.
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
