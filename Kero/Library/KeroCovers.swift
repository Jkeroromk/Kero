//
//  KeroCovers.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Box art for recognised games. Nothing is bundled: covers are fetched on the device from the
//  libretro thumbnail server (the same source RetroArch uses) and saved next to the library.
//  Users can also pick their own cover from Photos.
//

import SwiftData
import SwiftUI
import UIKit

import KeroEngine

@MainActor
enum KeroCovers
{
    private static var inFlight = Set<String>()

    static var isEnabled: Bool {
        return UserDefaults.standard.object(forKey: "downloadCovers") as? Bool ?? true
    }

    /// Downloads covers for games that have a known box art but no artwork yet.
    static func fetchMissing(for games: [KeroGame], context: ModelContext)
    {
        guard self.isEnabled else { return }

        for game in games where game.artworkFileName == nil
        {
            guard let boxart = game.boxartName,
                  let url = KeroGameDatabase.shared.coverURL(for: boxart, system: game.system),
                  !self.inFlight.contains(game.identifier)
            else { continue }

            self.inFlight.insert(game.identifier)
            let identifier = game.identifier

            Task {
                defer { self.inFlight.remove(identifier) }

                guard let data = try? await self.download(url),
                      let image = UIImage(data: data),
                      let png = image.pngData()
                else { return }

                do
                {
                    let fileName = try self.save(png, for: identifier)
                    game.artworkFileName = fileName
                    try? context.save()
                }
                catch
                {
                    // Covers are optional.
                }
            }
        }
    }

    /// A cover the user picked from Photos.
    static func setCustomCover(_ data: Data, for game: KeroGame, context: ModelContext)
    {
        guard let image = UIImage(data: data) else { return }

        // Keep it reasonably small; covers are shown at most a few hundred points wide.
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }

        guard let jpeg = resized.jpegData(compressionQuality: 0.88),
              let fileName = try? self.save(jpeg, for: game.identifier, fileExtension: "jpg")
        else { return }

        if let old = game.artworkURL, old.lastPathComponent != fileName
        {
            try? FileManager.default.removeItem(at: old)
        }

        game.artworkFileName = fileName
        try? context.save()
    }

    static func removeCover(of game: KeroGame, context: ModelContext)
    {
        if let url = game.artworkURL { try? FileManager.default.removeItem(at: url) }
        game.artworkFileName = nil
        game.boxartName = nil
        try? context.save()
    }

    private static func download(_ url: URL) async throws -> Data
    {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Saves under a fresh name each time so the image cache never shows a stale cover.
    private static func save(_ data: Data, for identifier: String, fileExtension: String = "png") throws -> String
    {
        try FileManager.default.createDirectory(at: KeroLibrary.artworkDirectory, withIntermediateDirectories: true)
        let fileName = "\(identifier)-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
        try data.write(to: KeroLibrary.artworkDirectory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }
}
