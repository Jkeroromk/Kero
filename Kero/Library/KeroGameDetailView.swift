//
//  KeroGameDetailView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  One game: cover, what Kero knows about it, play / load latest, its save-state slots and a few
//  facts about the file.
//

import SwiftUI

import KeroEngine

struct KeroGameDetailView: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame

    var body: some View
    {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 760
            let metrics = KeroHomeMetrics(size: geometry.size)

            ZStack {
                KeroHomeBackdrop(game: self.game,
                                 center: UnitPoint(x: isCompact ? 0.5 : 0.18, y: isCompact ? 0.12 : 0.3),
                                 radius: isCompact ? CGSize(width: 420, height: 360) : CGSize(width: 800 * metrics.scale, height: 600 * metrics.scale),
                                 fade: 0.68, intensity: 0.55, darkensBottom: false)

                if isCompact
                {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            self.header
                            HStack(alignment: .top, spacing: 16) {
                                self.cover(size: min(170, geometry.size.width * 0.42))
                                VStack(alignment: .leading, spacing: 10) {
                                    self.chips(fontSize: 11)
                                }
                            }
                            self.titleBlock(titleSize: 30)
                            self.actions(height: 46)
                            self.saveStates(columns: 2, thumbnailHeight: 92)
                            self.infoCards(columns: 1)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                    .scrollIndicators(.hidden)
                }
                else
                {
                    VStack(alignment: .leading, spacing: metrics.s(26)) {
                        self.header

                        HStack(alignment: .top, spacing: metrics.s(44)) {
                            self.cover(size: metrics.s(340))

                            VStack(alignment: .leading, spacing: metrics.s(22)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    self.chips(fontSize: 12)
                                    self.titleBlock(titleSize: metrics.font(52))
                                }
                                self.actions(height: metrics.s(52))
                                self.saveStates(columns: 4, thumbnailHeight: metrics.s(107))
                                Spacer(minLength: 0)
                                self.infoCards(columns: 3)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .padding(.top, metrics.s(26))
                    .padding(.horizontal, metrics.s(40))
                    .padding(.bottom, metrics.s(28))
                }
            }
        }
    }

    private var isRunning: Bool { self.model.isRunning(self.game) }

    // MARK: Header

    private var header: some View
    {
        let destination = self.model.detailReturnsTo == .home ? "Home" : "Library"

        return Button {
            self.model.closeDetails()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KeroTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(KeroTheme.surfaceStrong, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                Text(destination)
                    .font(.system(size: 14))
                    .foregroundStyle(KeroTheme.secondaryText)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeroPressStyle())
        .accessibilityLabel(Text("Back to \(destination)"))
    }

    // MARK: Cover

    private func cover(size: CGFloat) -> some View
    {
        VStack(spacing: 18) {
            KeroGameCover(game: self.game, cornerRadius: size * 0.076, labelsArtwork: true)
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size * 0.076, style: .continuous).strokeBorder(KeroTheme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: size * 0.1, y: size * 0.1)

            HStack(spacing: 8) {
                self.coverButton("Change cover") { self.model.host?.chooseCover(for: self.game) }
                self.coverButton("Rename") { self.model.host?.rename(self.game) }
            }
            .frame(width: size)
        }
    }

    private func coverButton(_ title: String, action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KeroTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .keroCard(cornerRadius: 12, fill: KeroTheme.surface, stroke: Color.white.opacity(0.1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(KeroPressStyle())
    }

    // MARK: Text

    @ViewBuilder
    private func chips(fontSize: CGFloat) -> some View
    {
        KeroFlowLayout(spacing: 8) {
            KeroChip(text: self.game.system.name, fontSize: fontSize)
            if let region = self.game.region, !region.isEmpty
            {
                KeroChip(text: region, fontSize: fontSize)
            }
            if self.game.isChineseTranslation
            {
                KeroChip(text: "汉化 · Chinese fan translation", fontSize: fontSize)
            }
            else if let languages = KeroFormat.languages(self.game.languages)
            {
                KeroChip(text: languages, fontSize: fontSize)
            }
            if self.game.officialTitle != nil
            {
                KeroChip(text: "Recognised", foreground: KeroTheme.recognised, background: KeroTheme.powerLED.opacity(0.14), fontSize: fontSize)
            }
        }
    }

    private func titleBlock(titleSize: CGFloat) -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.game.name)
                .font(.system(size: titleSize, weight: .heavy))
                .foregroundStyle(KeroTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.55)

            Text(self.playLine)
                .font(.system(size: 14))
                .foregroundStyle(KeroTheme.secondaryText)
        }
    }

    /// "Played 4 h 05 m · Last played 3 days ago · Added Oct 3"
    private var playLine: String {
        var parts: [String] = []
        if self.game.playSeconds > 0 { parts.append("Played " + KeroFormat.playTime(self.game.playSeconds)) }
        if self.isRunning { parts.append("Paused now") }
        else if let played = self.game.playedDate { parts.append("Last played " + KeroFormat.when(played).lowercasedFirst) }
        else { parts.append("Not played yet") }
        parts.append("Added " + KeroFormat.day(self.game.addedDate))
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func actions(height: CGFloat) -> some View
    {
        let latest = KeroSaveStates.shared.latest(for: self.game.identifier)

        return HStack(spacing: 10) {
            Button {
                KeroFeedback.select()
                self.model.play(self.game)
            } label: {
                KeroPrimaryPill(title: self.isRunning ? "Resume" : "Play", height: height, horizontalPadding: 30)
                    .keroFocusRing(self.isFocused(.play), shape: Capsule())
            }
            .buttonStyle(KeroPressStyle())

            Button {
                if let latest { self.model.load(latest, of: self.game) }
            } label: {
                KeroGlassPill(title: "Load latest save state", height: height, fontSize: 15, horizontalPadding: 20, isDisabled: latest == nil)
                    .keroFocusRing(self.isFocused(.loadLatest), shape: Capsule())
            }
            .buttonStyle(KeroPressStyle())
            .disabled(latest == nil)

            Button {
                self.model.toggleFavorite(self.game)
            } label: {
                KeroCircleIcon(symbol: self.game.isFavorite ? "star.fill" : "star", size: height,
                               tint: self.game.isFavorite ? KeroTheme.favorite : KeroTheme.primaryText)
                    .keroFocusRing(self.isFocused(.favorite), shape: Circle())
            }
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel(self.game.isFavorite ? "Remove from Favorites" : "Add to Favorites")

            Menu {
                if self.isRunning
                {
                    Button { self.model.restart(self.game) } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                }
                Button { self.model.host?.chooseCover(for: self.game) } label: {
                    Label("Choose Cover", systemImage: "photo")
                }
                if self.game.artworkFileName != nil
                {
                    Button { self.model.host?.removeCover(of: self.game) } label: {
                        Label("Remove Cover", systemImage: "photo.badge.minus")
                    }
                }
                Divider()
                Button(role: .destructive) { self.model.host?.confirmDelete(self.game) } label: {
                    Label("Delete Game", systemImage: "trash")
                }
            } label: {
                KeroCircleIcon(symbol: "ellipsis", size: height)
            }
            .menuStyle(.button)
            .buttonStyle(KeroPressStyle())
            .accessibilityLabel("More options")
        }
    }

    private func isFocused(_ focus: KeroDetailFocus) -> Bool
    {
        return self.model.showsFocus && self.model.section == .details && self.model.detailFocus == focus
    }

    // MARK: Save states

    private func saveStates(columns: Int, thumbnailHeight: CGFloat) -> some View
    {
        let store = KeroSaveStates.shared
        let hasAny = store.latest(for: self.game.identifier) != nil
        let hint = self.isRunning ? "Hold a slot to overwrite or delete" : (hasAny ? "Hold a slot to delete it" : "Save states made in the pause menu appear here")

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Save states")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KeroTheme.primaryText)
                Spacer(minLength: 8)
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(KeroTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: columns), spacing: 12) {
                ForEach(Array(KeroSaveStates.allSlots.enumerated()), id: \.element) { index, slot in
                    KeroSlotCell(model: self.model, game: self.game, slot: slot,
                                 state: store.state(for: self.game.identifier, slot: slot),
                                 canSave: self.isRunning,
                                 thumbnailHeight: thumbnailHeight,
                                 isFocused: self.isFocused(.slot(index)))
                }
            }
        }
    }

    // MARK: Info

    private func infoCards(columns: Int) -> some View
    {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: columns), spacing: 12) {
            self.infoCard("In-game save", self.batterySaveText)
            self.infoCard("File", self.fileText)
            self.infoCard("Controls", self.game.system == .nintendoDS ? "Touch + controller" : "Controller or touch")
        }
    }

    private func infoCard(_ title: String, _ value: String) -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(KeroTheme.secondaryText)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KeroTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .keroCard(cornerRadius: 16, fill: Color.white.opacity(0.04), stroke: Color.white.opacity(0.07))
        .accessibilityElement(children: .combine)
    }

    /// The cartridge's own save (battery RAM), written by the game.
    private var batterySaveText: String {
        let url = KeroGameStorage.default.batterySaveURL(forGame: self.game.identifier)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue > 0,
              let date = attributes[.modificationDate] as? Date
        else { return "No save yet" }
        return "Saved " + KeroFormat.when(date).lowercasedFirst
    }

    private var fileText: String {
        let url = self.game.romURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        let ext = "." + url.pathExtension.lowercased()
        guard let size else { return ext }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file) + " · " + ext
    }
}

// MARK: - Slot cell -

private struct KeroSlotCell: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    let slot: Int
    let state: KeroSaveState?
    /// The game is the one paused right now, so its current moment can be saved here.
    let canSave: Bool
    let thumbnailHeight: CGFloat
    let isFocused: Bool

    var body: some View
    {
        Button {
            if let state = self.state
            {
                self.model.load(state, of: self.game)
            }
            else if self.canSave
            {
                KeroFeedback.select()
                self.model.host?.saveNowPlaying(to: self.slot)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                KeroSaveStateThumbnail(state: self.state, system: self.game.system, cornerRadius: 10, splitsDualScreen: true)
                    .frame(height: self.thumbnailHeight)
                Text(KeroSaveStates.name(of: self.slot))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KeroTheme.primaryText)
                    .padding(.horizontal, 4)
                Text(self.state?.detail ?? (self.canSave ? "Empty slot · tap to save" : "Empty slot"))
                    .font(.system(size: 12))
                    .foregroundStyle(KeroTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .keroCard(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .keroFocusRing(self.isFocused, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(KeroPressStyle())
        .disabled(self.state == nil && !self.canSave)
        .contextMenu {
            if let state = self.state
            {
                Button { self.model.load(state, of: self.game) } label: {
                    Label("Load", systemImage: "play.fill")
                }
            }
            if self.canSave
            {
                Button { self.model.host?.saveNowPlaying(to: self.slot) } label: {
                    Label(self.state == nil ? "Save Here" : "Overwrite with Current Game", systemImage: "square.and.arrow.down")
                }
            }
            if self.state != nil
            {
                Button(role: .destructive) {
                    KeroSaveStates.shared.delete(gameID: self.game.identifier, slot: self.slot)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel(Text("\(KeroSaveStates.name(of: self.slot)), \(self.state?.detail ?? "empty")"))
    }
}

// MARK: - Flow layout -

/// Lays chips out in rows, wrapping when they don't fit.
struct KeroFlowLayout: Layout
{
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize
    {
        let rows = self.rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + self.spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
    {
        var y = bounds.minY
        for row in self.rows(width: bounds.width, subviews: subviews)
        {
            var x = bounds.minX
            for index in row.indices
            {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + self.spacing
            }
            y += row.height + self.spacing
        }
    }

    private struct Row
    {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row]
    {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices
        {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + self.spacing + size.width
            if needed > width && !current.indices.isEmpty
            {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + self.spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
