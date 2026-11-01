//
//  KeroLiveArea.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  The game card that opens when you pick a bubble: big artwork, details and a Start button.
//

import SwiftUI

import KeroEngine

struct KeroLiveArea: View
{
    @ObservedObject var model: KeroHomeModel
    let game: KeroGame
    let palette: KeroTheme.Palette

    @State private var dragOffset: CGFloat = 0

    var body: some View
    {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height * 1.15
            let artworkSize = isWide ? min(geometry.size.height * 0.62, geometry.size.width * 0.36) : min(geometry.size.width * 0.62, geometry.size.height * 0.36)

            ZStack(alignment: .topLeading) {
                // Backdrop tinted with the system color, over a blur of the home screen.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(colors: [self.tint.opacity(0.55), self.palette.skyTop.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .ignoresSafeArea()
                    .onTapGesture { }

                Group {
                    if isWide
                    {
                        HStack(alignment: .center, spacing: geometry.size.width * 0.05) {
                            self.artwork(size: artworkSize)
                            self.details(alignment: .leading)
                                .frame(maxWidth: geometry.size.width * 0.48, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    else
                    {
                        VStack(spacing: 24) {
                            Spacer(minLength: 0)
                            self.artwork(size: artworkSize)
                            self.details(alignment: .center)
                                .padding(.horizontal, 24)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.vertical, 20)

                Button {
                    self.model.closeLiveArea()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .keroGlass(Circle(), palette: self.palette)
                }
                .padding(.leading, 20)
                .padding(.top, 12)
                .accessibilityLabel(Text("Close"))
            }
            .offset(y: max(0, self.dragOffset))
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if value.translation.height > 0 { self.dragOffset = value.translation.height }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 260
                        {
                            self.model.closeLiveArea()
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.dragOffset = 0 }
                    }
            )
        }
    }
}

private extension KeroLiveArea
{
    var tint: Color {
        return KeroTheme.tint(for: self.game.system)
    }

    var isRunning: Bool {
        return self.model.isRunning(self.game)
    }

    func isFocused(_ button: KeroLiveAreaButton) -> Bool
    {
        return self.model.showsFocus && self.model.liveAreaFocus == button
    }

    func artwork(size: CGFloat) -> some View
    {
        KeroArtworkImage(url: self.game.artworkURL) {
            KeroArtworkPlaceholder(system: self.game.system, name: self.game.name)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .overlay(
            // Gloss sweep across the top of the card.
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: Color.white.opacity(0.45), location: 0),
                    .init(color: Color.white.opacity(0.08), location: 0.45),
                    .init(color: Color.white.opacity(0), location: 0.46),
                ], startPoint: .top, endPoint: .bottom))
                .blendMode(.screen)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
        .rotation3DEffect(.degrees(self.isRunning ? 0 : -4), axis: (x: 0, y: 1, z: 0))
    }

    func details(alignment: HorizontalAlignment) -> some View
    {
        VStack(alignment: alignment, spacing: 14) {
            HStack(spacing: 8) {
                Text(self.game.system.name)
                    .font(KeroTheme.font(13, .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(self.tint))
                    .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))

                if self.isRunning
                {
                    HStack(spacing: 5) {
                        KeroRunningBadge(size: 16)
                        Text("Playing now")
                            .font(KeroTheme.font(13, .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            Text(self.game.name)
                .font(KeroTheme.font(30, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)

            Text(self.lastPlayedText)
                .font(KeroTheme.font(15, .medium))
                .foregroundStyle(self.palette.secondaryText)

            self.buttons
                .padding(.top, 10)
        }
    }

    var buttons: some View {
        let green = Color(red: 0.12, green: 0.72, blue: 0.32)
        let orange = Color(red: 0.98, green: 0.55, blue: 0.12)
        let red = Color(red: 0.90, green: 0.22, blue: 0.24)
        let glass = Color.white.opacity(0.22)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { self.buttonRow(green: green, orange: orange, red: red, glass: glass) }
            VStack(spacing: 12) { self.buttonRow(green: green, orange: orange, red: red, glass: glass) }
        }
    }

    @ViewBuilder
    func buttonRow(green: Color, orange: Color, red: Color, glass: Color) -> some View
    {
        Button {
            self.model.perform(.start, for: self.game)
        } label: {
            Label(self.isRunning ? "Resume" : "Start", systemImage: "play.fill")
                .padding(.horizontal, 10)
        }
        .buttonStyle(KeroGlossyButtonStyle(tint: green, isFocused: self.isFocused(.start), palette: self.palette))

        if self.isRunning
        {
            Button {
                self.model.perform(.restart, for: self.game)
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(KeroGlossyButtonStyle(tint: orange, isFocused: self.isFocused(.restart), palette: self.palette))
        }

        Button {
            self.model.perform(.favorite, for: self.game)
        } label: {
            Image(systemName: self.game.isFavorite ? "star.fill" : "star")
                .accessibilityLabel(Text(self.game.isFavorite ? "Remove Favorite" : "Add Favorite"))
        }
        .buttonStyle(KeroGlossyButtonStyle(tint: self.game.isFavorite ? Color(red: 0.95, green: 0.70, blue: 0.10) : glass, isFocused: self.isFocused(.favorite), palette: self.palette))

        Button {
            self.model.perform(.delete, for: self.game)
        } label: {
            Image(systemName: "trash")
                .accessibilityLabel(Text("Delete"))
        }
        .buttonStyle(KeroGlossyButtonStyle(tint: red.opacity(0.85), isFocused: self.isFocused(.delete), palette: self.palette))
    }

    var lastPlayedText: String {
        guard let playedDate = self.game.playedDate else {
            return NSLocalizedString("Never played", comment: "")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: playedDate, relativeTo: Date())
        return String(format: NSLocalizedString("Last played %@", comment: ""), relative)
    }
}
