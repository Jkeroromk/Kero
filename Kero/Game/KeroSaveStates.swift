//
//  KeroSaveStates.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Save-state slots: three manual slots plus an auto save written when the iPhone folds or the app
//  goes to the background mid-game. Each state is KeroEngine's `slot-N.state`, with a small PNG of
//  the screen (`slot-N.png`) and when/why it was saved (`slot-N.json`) next to it. States from
//  before slots existed are `slot-1.state` with nothing beside them: they show up as Slot 1, dated
//  by the file.
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UIKit

import KeroEngine

struct KeroSaveState: Identifiable, Hashable
{
    enum Reason: String, Codable
    {
        case manual
        case folded
        case background
    }

    let gameID: String
    let slot: Int
    let date: Date
    let reason: Reason?
    let thumbnailURL: URL?

    var id: Int { self.slot }
    var isAuto: Bool { self.slot == KeroSaveStates.autoSlot }
    var name: String { KeroSaveStates.name(of: self.slot) }

    /// "Today 9:42", or for the auto save "Folded · Today 9:42".
    var detail: String {
        let stamp = KeroFormat.stamp(self.date)
        switch self.reason
        {
        case .folded?: return "Folded · " + stamp
        case .background?: return "Left the app · " + stamp
        default: return stamp
        }
    }
}

@MainActor
@Observable
final class KeroSaveStates
{
    static let shared = KeroSaveStates()

    nonisolated static let autoSlot = 0
    nonisolated static let manualSlots = [1, 2, 3]
    /// In the order the details screen shows them.
    nonisolated static let allSlots = [1, 2, 3, 0]

    nonisolated static func name(of slot: Int) -> String
    {
        return slot == self.autoSlot ? "Auto save" : "Slot \(slot)"
    }

    /// Bumped on every write or delete, so views that list states refresh.
    private(set) var revision = 0

    @ObservationIgnored private var cache: [String: [KeroSaveState]] = [:]
    @ObservationIgnored private let storage = KeroGameStorage.default

    private struct Info: Codable
    {
        var savedAt: Date
        var reason: KeroSaveState.Reason
    }

    // MARK: Reading

    /// Existing states, newest first.
    func states(for gameID: String) -> [KeroSaveState]
    {
        _ = self.revision
        if let cached = self.cache[gameID] { return cached }

        let states = Self.allSlots.compactMap { self.read(gameID: gameID, slot: $0) }.sorted { $0.date > $1.date }
        self.cache[gameID] = states
        return states
    }

    func state(for gameID: String, slot: Int) -> KeroSaveState?
    {
        return self.states(for: gameID).first { $0.slot == slot }
    }

    func latest(for gameID: String) -> KeroSaveState?
    {
        return self.states(for: gameID).first
    }

    func data(for gameID: String, slot: Int) throws -> Data
    {
        return try self.storage.readSaveState(forGame: gameID, slot: slot)
    }

    /// "Save to a new slot": the first empty manual slot, otherwise the oldest one (returned as `replaces`).
    func slotForNewSave(gameID: String) -> (slot: Int, replaces: KeroSaveState?)
    {
        let manual = self.states(for: gameID).filter { !$0.isAuto }
        if let free = Self.manualSlots.first(where: { slot in !manual.contains { $0.slot == slot } })
        {
            return (free, nil)
        }

        let oldest = manual.min { $0.date < $1.date }
        return (oldest?.slot ?? Self.manualSlots[0], oldest)
    }

    /// The manual slot saved to most recently, or Slot 1.
    func quickSaveSlot(gameID: String) -> Int
    {
        return self.states(for: gameID).first { !$0.isAuto }?.slot ?? Self.manualSlots[0]
    }

    // MARK: Writing

    func write(_ data: Data, thumbnail: Data?, gameID: String, slot: Int, reason: KeroSaveState.Reason) throws
    {
        try self.storage.writeSaveState(data, forGame: gameID, slot: slot)

        let stateURL = self.storage.saveStateURL(forGame: gameID, slot: slot)
        let thumbnailURL = Self.thumbnailURL(for: stateURL)
        if let thumbnail
        {
            try? thumbnail.write(to: thumbnailURL, options: .atomic)
        }
        else
        {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }

        let info = Info(savedAt: Date(), reason: reason)
        if let json = try? JSONEncoder().encode(info)
        {
            try? json.write(to: Self.infoURL(for: stateURL), options: .atomic)
        }

        self.invalidate(gameID)
    }

    func delete(gameID: String, slot: Int)
    {
        let stateURL = self.storage.saveStateURL(forGame: gameID, slot: slot)
        for url in [stateURL, Self.thumbnailURL(for: stateURL), Self.infoURL(for: stateURL)]
        {
            try? FileManager.default.removeItem(at: url)
        }
        self.invalidate(gameID)
    }

    // MARK: Helpers

    private func invalidate(_ gameID: String)
    {
        self.cache[gameID] = nil
        self.revision += 1
    }

    private func read(gameID: String, slot: Int) -> KeroSaveState?
    {
        let stateURL = self.storage.saveStateURL(forGame: gameID, slot: slot)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: stateURL.path) else { return nil }

        var date = attributes[.modificationDate] as? Date ?? .distantPast
        var reason: KeroSaveState.Reason?
        if let data = try? Data(contentsOf: Self.infoURL(for: stateURL)), let info = try? JSONDecoder().decode(Info.self, from: data)
        {
            date = info.savedAt
            reason = info.reason
        }

        let thumbnailURL = Self.thumbnailURL(for: stateURL)
        let hasThumbnail = FileManager.default.fileExists(atPath: thumbnailURL.path)
        return KeroSaveState(gameID: gameID, slot: slot, date: date, reason: reason, thumbnailURL: hasThumbnail ? thumbnailURL : nil)
    }

    private static func thumbnailURL(for stateURL: URL) -> URL
    {
        return stateURL.deletingPathExtension().appendingPathExtension("png")
    }

    private static func infoURL(for stateURL: URL) -> URL
    {
        return stateURL.deletingPathExtension().appendingPathExtension("json")
    }
}

// MARK: - Screen snapshots -

enum KeroFrameSnapshot
{
    /// The emulator's latest frame as a PNG at its native size (240×160 for GBA, 256×384 for DS).
    static func pngData(from frameBuffer: KeroFrameBuffer) -> Data?
    {
        guard let image = self.image(from: frameBuffer) else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    static func image(from frameBuffer: KeroFrameBuffer) -> CGImage?
    {
        let copied: (pixels: Data, width: Int, height: Int)? = frameBuffer.withLatestFrame { (frame: KeroFrameBuffer.Frame) -> (pixels: Data, width: Int, height: Int)? in
            let width = frame.format.width
            let height = frame.format.height
            guard width > 0, height > 0 else { return nil }

            var pixels = Data(count: width * height * 4)
            pixels.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                guard let base = destination.baseAddress else { return }

                for y in 0 ..< height
                {
                    let source = frame.bytes.advanced(by: y * frame.bytesPerRow)
                    let row = base.advanced(by: y * width * 4)

                    switch frame.format.pixelFormat
                    {
                    case .rgbx8888:
                        row.copyMemory(from: source, byteCount: width * 4)

                    case .rgb565:
                        let out = row.assumingMemoryBound(to: UInt8.self)
                        for x in 0 ..< width
                        {
                            let value = source.loadUnaligned(fromByteOffset: x * 2, as: UInt16.self)
                            let r = UInt8((value >> 11) & 0x1F), g = UInt8((value >> 5) & 0x3F), b = UInt8(value & 0x1F)
                            out[x * 4] = (r << 3) | (r >> 2)
                            out[x * 4 + 1] = (g << 2) | (g >> 4)
                            out[x * 4 + 2] = (b << 3) | (b >> 2)
                            out[x * 4 + 3] = 255
                        }
                    }
                }
            }
            return (pixels, width, height)
        } ?? nil

        guard let copied, let provider = CGDataProvider(data: copied.pixels as CFData) else { return nil }

        return CGImage(width: copied.width, height: copied.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: copied.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Thumbnail view -

private final class KeroThumbnailCache: @unchecked Sendable
{
    static let shared = KeroThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for url: URL, version: Date) -> UIImage?
    {
        let key = "\(url.path)#\(version.timeIntervalSinceReferenceDate)" as NSString
        if let image = self.cache.object(forKey: key) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        self.cache.setObject(image, forKey: key)
        return image
    }
}

/// A save state's picture. Nintendo DS states show both screens, one above the other.
struct KeroSaveStateThumbnail: View
{
    var state: KeroSaveState?
    var system: KeroSystem
    var cornerRadius: CGFloat = 8
    /// Splits DS pictures into two screens with a small gap (the details screen); off for small rows.
    var splitsDualScreen = false

    var body: some View
    {
        let image = self.state.flatMap { state in state.thumbnailURL.flatMap { KeroThumbnailCache.shared.image(for: $0, version: state.date) } }

        Group {
            if let image
            {
                if self.splitsDualScreen && self.system == .nintendoDS
                {
                    GeometryReader { geometry in
                        let gap: CGFloat = 3
                        let half = (geometry.size.height - gap) / 2
                        VStack(spacing: gap) {
                            self.half(image, top: true).frame(height: half)
                            self.half(image, top: false).frame(height: half)
                        }
                    }
                }
                else if self.system == .nintendoDS
                {
                    // Small rows: just the top screen.
                    self.half(image, top: true)
                }
                else
                {
                    Color.clear.overlay {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                    }
                    .clipped()
                }
            }
            else if self.state != nil
            {
                // A state without a picture (saved before Kero kept them).
                LinearGradient(colors: [KeroTheme.tint(for: self.system).lighter(0.1), KeroTheme.tint(for: self.system).darker(0.1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
            else
            {
                if self.splitsDualScreen && self.system == .nintendoDS
                {
                    VStack(spacing: 3) {
                        Color.white.opacity(0.06)
                        Color.white.opacity(0.04)
                    }
                }
                else
                {
                    Color.white.opacity(0.06)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func half(_ image: UIImage, top: Bool) -> some View
    {
        Color.clear.overlay {
            GeometryReader { geometry in
                // The picture is twice as tall as one screen: scale it to fill one half, and show the right half.
                let scale = max(geometry.size.width / image.size.width, geometry.size.height * 2 / image.size.height)
                let height = image.size.height * scale
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: image.size.width * scale, height: height)
                    .offset(x: (geometry.size.width - image.size.width * scale) / 2,
                            y: geometry.size.height / 2 - height * (top ? 0.25 : 0.75))
            }
        }
        .clipped()
    }
}
