//
//  KeroConsoleShell.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  The handheld's body: graphite shell, screen bezel, power light, wordmark and speaker grille.
//  Drawn behind the picture and the touch controls.
//

import SwiftUI

import KeroEngine

struct KeroConsoleShell: View
{
    let layout: KeroConsoleLayout
    let system: KeroSystem
    /// Power light is on while the game runs, dims while paused.
    let isRunning: Bool

    var body: some View
    {
        ZStack(alignment: .topLeading) {
            // Body
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.105), Color(white: 0.085)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.05), .clear],
                           center: .top, startRadius: 0, endRadius: max(self.layout.size.width, self.layout.size.height) * 0.7)

            // Hinge groove between the two halves of the clamshell.
            if !self.layout.hinge.isEmpty
            {
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.45)).frame(height: 2)
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                }
                .frame(width: self.layout.size.width)
                .position(x: self.layout.hinge.midX, y: self.layout.hinge.midY)

                Rectangle()
                    .fill(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.18), .black.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: self.layout.size.width, height: self.layout.hinge.height)
                    .position(x: self.layout.hinge.midX, y: self.layout.hinge.midY)
            }

            // Bezel
            RoundedRectangle(cornerRadius: self.bezelRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.055), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: self.bezelRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .frame(width: self.layout.bezel.width, height: self.layout.bezel.height)
                .position(x: self.layout.bezel.midX, y: self.layout.bezel.midY)

            // DS: second bezel for the touch screen.
            if !self.layout.bottomBezel.isEmpty
            {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.055), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    .frame(width: self.layout.bottomBezel.width, height: self.layout.bottomBezel.height)
                    .position(x: self.layout.bottomBezel.midX, y: self.layout.bottomBezel.midY)

                Rectangle()
                    .fill(Color.black)
                    .frame(width: self.layout.bottomScreen.width + 2, height: self.layout.bottomScreen.height + 2)
                    .position(x: self.layout.bottomScreen.midX, y: self.layout.bottomScreen.midY)
            }

            // Black behind the picture so its edges stay crisp.
            Rectangle()
                .fill(Color.black)
                .frame(width: self.layout.screen.width + 2, height: self.layout.screen.height + 2)
                .position(x: self.layout.screen.midX, y: self.layout.screen.midY)

            if !self.layout.label.isEmpty
            {
                self.labelStrip
                    .frame(width: self.layout.label.width, height: self.layout.label.height)
                    .position(x: self.layout.label.midX, y: self.layout.label.midY)
            }
            else
            {
                // Landscape: just the power light in the bezel's corner.
                self.powerLight
                    .position(x: self.layout.bezel.minX + 9, y: self.layout.bezel.minY + 9)
            }

            if !self.layout.speaker.isEmpty
            {
                KeroSpeakerGrille()
                    .frame(width: self.layout.speaker.width, height: self.layout.speaker.height)
                    .position(x: self.layout.speaker.midX, y: self.layout.speaker.midY)
            }
        }
        .frame(width: self.layout.size.width, height: self.layout.size.height)
        .allowsHitTesting(false)
    }

    private var bezelRadius: CGFloat {
        return self.layout.style == .portrait ? 14 : 12
    }

    private var labelStrip: some View
    {
        HStack(spacing: 7) {
            self.powerLight
            Text("POWER")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.28))

            Spacer(minLength: 8)

            Text(self.system.name.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("KERO")
                .font(.system(size: 11, weight: .heavy))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 2)
    }

    private var powerLight: some View
    {
        let color = Color(red: 0.35, green: 0.95, blue: 0.55)
        return Circle()
            .fill(self.isRunning ? color : color.opacity(0.25))
            .frame(width: 6, height: 6)
            .shadow(color: self.isRunning ? color.opacity(0.9) : .clear, radius: 4)
            .animation(.easeInOut(duration: 0.3), value: self.isRunning)
    }
}

/// Grid of small holes, slanted like a Game Boy's speaker.
private struct KeroSpeakerGrille: View
{
    var body: some View
    {
        Canvas { context, size in
            let rows = 4
            let columns = 6
            let spacing = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
            let dot = spacing * 0.36

            for row in 0 ..< rows
            {
                for column in 0 ..< columns
                {
                    let x = CGFloat(column) * spacing + CGFloat(rows - 1 - row) * spacing * 0.35 + spacing / 2
                    let y = CGFloat(row) * spacing + spacing / 2
                    guard x + dot / 2 <= size.width else { continue }

                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.55)))
                    context.stroke(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 0.5)), with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                }
            }
        }
    }
}

/// The round menu button on the body (or a glass one floating over a full-screen picture).
struct KeroHomeButton: View
{
    var isOverlay: Bool
    var action: () -> Void

    var body: some View
    {
        Button(action: self.action) {
            ZStack {
                if self.isOverlay
                {
                    Circle().fill(.ultraThinMaterial.opacity(0.7))
                }
                else
                {
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                }

                Image(systemName: self.isOverlay ? "pause.fill" : "line.3.horizontal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(KeroPressStyle())
        .accessibilityLabel("Menu")
    }
}
