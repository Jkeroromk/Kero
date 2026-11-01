//
//  KeroBackground.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Animated sky: gradient, two glossy light ribbons and slowly rising bubbles.
//

import SwiftUI

struct KeroBackground: View
{
    var palette: KeroTheme.Palette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bubbles: [KeroBackgroundBubble] = {
        var generator = SeededGenerator(seed: 0x4B65726F)
        return (0..<18).map { _ in KeroBackgroundBubble(using: &generator) }
    }()

    var body: some View
    {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: self.reduceMotion)) { timeline in
            let time = self.reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                self.drawSky(in: &context, size: size)
                self.drawRibbons(in: &context, size: size, time: time)
                self.drawBubbles(in: &context, size: size, time: time)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private extension KeroBackground
{
    func drawSky(in context: inout GraphicsContext, size: CGSize)
    {
        let rect = CGRect(origin: .zero, size: size)
        let gradient = Gradient(stops: [
            .init(color: self.palette.skyTop, location: 0),
            .init(color: self.palette.skyMiddle, location: 0.55),
            .init(color: self.palette.skyBottom, location: 1),
        ])
        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))

        // Soft sun glow in the top-right corner.
        let glowRadius = max(size.width, size.height) * 0.6
        let glowCenter = CGPoint(x: size.width * 0.9, y: size.height * 0.05)
        context.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)]),
                                                       center: glowCenter, startRadius: 0, endRadius: glowRadius))
    }

    func drawRibbons(in context: inout GraphicsContext, size: CGSize, time: TimeInterval)
    {
        let ribbons: [(baseline: CGFloat, amplitude: CGFloat, wavelength: CGFloat, speed: Double, thickness: CGFloat, opacity: Double)] = [
            (0.68, 0.06, 1.4, 0.10, 0.10, 0.28),
            (0.74, 0.045, 1.0, -0.07, 0.06, 0.20),
            (0.62, 0.03, 0.8, 0.05, 0.03, 0.18),
        ]

        for ribbon in ribbons
        {
            var top = Path()
            var bottom = [CGPoint]()

            let steps = 48
            for step in 0...steps
            {
                let x = size.width * CGFloat(step) / CGFloat(steps)
                let phase = (Double(x / size.width) / Double(ribbon.wavelength) + time * ribbon.speed) * 2 * .pi
                let y = size.height * (ribbon.baseline + ribbon.amplitude * CGFloat(sin(phase)))
                let thickness = size.height * ribbon.thickness * CGFloat(0.6 + 0.4 * cos(phase * 0.5))

                if step == 0 { top.move(to: CGPoint(x: x, y: y)) } else { top.addLine(to: CGPoint(x: x, y: y)) }
                bottom.append(CGPoint(x: x, y: y + thickness))
            }

            for point in bottom.reversed() { top.addLine(to: point) }
            top.closeSubpath()

            let gradient = Gradient(colors: [self.palette.ribbon.opacity(ribbon.opacity), self.palette.ribbon.opacity(0)])
            context.fill(top, with: .linearGradient(gradient,
                                                    startPoint: CGPoint(x: 0, y: size.height * (ribbon.baseline - ribbon.amplitude)),
                                                    endPoint: CGPoint(x: 0, y: size.height * (ribbon.baseline + ribbon.amplitude + ribbon.thickness))))
        }
    }

    func drawBubbles(in context: inout GraphicsContext, size: CGSize, time: TimeInterval)
    {
        let unit = min(size.width, size.height)

        for bubble in Self.bubbles
        {
            let radius = unit * bubble.radius
            let travel = size.height + radius * 4
            let progress = (bubble.offset + time * bubble.speed).truncatingRemainder(dividingBy: 1)
            let y = size.height + radius * 2 - CGFloat(progress) * travel
            let x = size.width * bubble.x + CGFloat(sin(time * bubble.wobbleSpeed + bubble.offset * 10)) * unit * 0.02

            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let circle = Path(ellipseIn: rect)

            context.fill(circle, with: .radialGradient(Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.10 * bubble.alpha), Color.white.opacity(0.35 * bubble.alpha)]),
                                                       center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: radius))
            context.stroke(circle, with: .color(Color.white.opacity(0.35 * bubble.alpha)), lineWidth: 0.8)

            // Specular highlight
            let highlight = CGRect(x: rect.minX + radius * 0.35, y: rect.minY + radius * 0.25, width: radius * 0.6, height: radius * 0.35)
            context.fill(Path(ellipseIn: highlight), with: .color(Color.white.opacity(0.45 * bubble.alpha)))
        }
    }
}

private struct KeroBackgroundBubble
{
    var x: CGFloat
    var radius: CGFloat
    var speed: Double
    var offset: Double
    var wobbleSpeed: Double
    var alpha: Double

    init<G: RandomNumberGenerator>(using generator: inout G)
    {
        self.x = CGFloat.random(in: 0...1, using: &generator)
        self.radius = CGFloat.random(in: 0.012...0.06, using: &generator)
        self.speed = Double.random(in: 0.006...0.02, using: &generator)
        self.offset = Double.random(in: 0...1, using: &generator)
        self.wobbleSpeed = Double.random(in: 0.3...0.9, using: &generator)
        self.alpha = Double.random(in: 0.5...1.0, using: &generator)
    }
}

/// Small deterministic generator so the bubble field looks the same every launch.
private struct SeededGenerator: RandomNumberGenerator
{
    private var state: UInt64

    init(seed: UInt64)
    {
        self.state = seed
    }

    mutating func next() -> UInt64
    {
        // SplitMix64
        self.state &+= 0x9E3779B97F4A7C15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
