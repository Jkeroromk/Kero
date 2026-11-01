//
//  KeroTouchController.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  On-screen controller built on raw UIKit multitouch (not SwiftUI gestures), so presses
//  register immediately, several buttons can be held at once, and a thumb can slide
//  across the D-pad or between A and B.
//

import SwiftUI
import UIKit

import KeroEngine

struct KeroTouchController: UIViewRepresentable
{
    enum Layout
    {
        /// Controls fill the area below the game screen.
        case portrait
        /// Controls float over the edges of a full-screen game.
        case landscape
    }

    var system: KeroSystem
    var layout: Layout
    var onChange: (KeroButtons) -> Void

    func makeUIView(context: Context) -> KeroTouchControllerView
    {
        let view = KeroTouchControllerView()
        view.buttonsChanged = self.onChange
        view.configure(system: self.system, layout: self.layout)
        return view
    }

    func updateUIView(_ view: KeroTouchControllerView, context: Context)
    {
        view.buttonsChanged = self.onChange
        view.configure(system: self.system, layout: self.layout)
    }

    static func dismantleUIView(_ view: KeroTouchControllerView, coordinator: ())
    {
        view.releaseAll()
    }
}

final class KeroTouchControllerView: UIView
{
    var buttonsChanged: ((KeroButtons) -> Void)?

    private enum Kind: Equatable
    {
        case dpad
        case button(KeroButtons, label: String, shape: Shape)
    }

    private enum Shape: Equatable
    {
        case circle
        case pill
        case shoulder
    }

    private struct Control
    {
        var kind: Kind
        var frame: CGRect
        var hitFrame: CGRect
        var layer: CALayer
        var highlight: CALayer
    }

    private var system: KeroSystem = .gameBoyAdvance
    private var layout: KeroTouchController.Layout = .portrait
    private var controls: [Control] = []
    private var dpadArmLayers: [KeroButtons: CALayer] = [:]

    private var touchButtons: [ObjectIdentifier: KeroButtons] = [:]
    private var current: KeroButtons = []

    private let pressFeedback = UIImpactFeedbackGenerator(style: .light)
    private let slideFeedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect)
    {
        super.init(frame: frame)

        self.isMultipleTouchEnabled = true
        self.isExclusiveTouch = false
        self.backgroundColor = .clear
        self.pressFeedback.prepare()
        self.slideFeedback.prepare()
    }

    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(system: KeroSystem, layout: KeroTouchController.Layout)
    {
        guard system != self.system || layout != self.layout || self.controls.isEmpty else { return }

        self.system = system
        self.layout = layout
        self.setNeedsLayout()
    }

    func releaseAll()
    {
        self.touchButtons.removeAll()
        self.update()
    }

    // MARK: Hit testing

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool
    {
        // In landscape the view covers the game; only the controls themselves take touches.
        guard self.layout == .landscape else { return super.point(inside: point, with: event) }
        return self.controls.contains { $0.hitFrame.contains(point) }
    }

    // MARK: Layout & skin

    override func layoutSubviews()
    {
        super.layoutSubviews()
        self.rebuildControls()
    }

    private var hasShoulders: Bool {
        return self.system == .gameBoyAdvance || self.system == .snes
    }

    private func rebuildControls()
    {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        self.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.controls.removeAll()
        self.dpadArmLayers.removeAll()

        let bounds = self.bounds.inset(by: self.layout == .landscape ? self.safeAreaInsets : .zero)
        guard bounds.width > 50, bounds.height > 50 else { return }

        let opacity: Float = self.layout == .landscape ? 0.6 : 1.0

        switch self.layout
        {
        case .portrait:
            let margin = max(18, bounds.width * 0.06)
            let dpadSize = min(bounds.width * 0.40, bounds.height * 0.52, 176)
            let faceSize = dpadSize * 0.40
            let centerY = bounds.minY + bounds.height * (self.hasShoulders ? 0.47 : 0.42)

            if self.hasShoulders
            {
                let shoulder = CGSize(width: min(110, bounds.width * 0.26), height: 38)
                self.addButton(.l, "L", .shoulder, CGRect(x: bounds.minX + margin, y: bounds.minY + 8, width: shoulder.width, height: shoulder.height), opacity)
                self.addButton(.r, "R", .shoulder, CGRect(x: bounds.maxX - margin - shoulder.width, y: bounds.minY + 8, width: shoulder.width, height: shoulder.height), opacity)
            }

            self.addDPad(CGRect(x: bounds.minX + margin, y: centerY - dpadSize / 2, width: dpadSize, height: dpadSize), opacity)

            let aCenter = CGPoint(x: bounds.maxX - margin - faceSize / 2, y: centerY - faceSize * 0.38)
            let bCenter = CGPoint(x: aCenter.x - faceSize * 1.22, y: centerY + faceSize * 0.38)
            self.addButton(.b, "B", .circle, CGRect(x: bCenter.x - faceSize / 2, y: bCenter.y - faceSize / 2, width: faceSize, height: faceSize), opacity)
            self.addButton(.a, "A", .circle, CGRect(x: aCenter.x - faceSize / 2, y: aCenter.y - faceSize / 2, width: faceSize, height: faceSize), opacity)

            let pill = CGSize(width: 70, height: 28)
            let pillY = min(bounds.maxY - pill.height - 16, centerY + dpadSize / 2 + 24)
            self.addButton(.select, "SELECT", .pill, CGRect(x: bounds.midX - pill.width - 12, y: pillY, width: pill.width, height: pill.height), opacity)
            self.addButton(.start, "START", .pill, CGRect(x: bounds.midX + 12, y: pillY, width: pill.width, height: pill.height), opacity)

        case .landscape:
            let margin: CGFloat = 20
            let dpadSize = min(bounds.height * 0.42, 168)
            let faceSize = dpadSize * 0.40
            let bottom = bounds.maxY - 16

            if self.hasShoulders
            {
                let shoulder = CGSize(width: 100, height: 36)
                self.addButton(.l, "L", .shoulder, CGRect(x: bounds.minX + margin, y: bounds.minY + 12, width: shoulder.width, height: shoulder.height), opacity)
                self.addButton(.r, "R", .shoulder, CGRect(x: bounds.maxX - margin - shoulder.width, y: bounds.minY + 12, width: shoulder.width, height: shoulder.height), opacity)
            }

            let dpadFrame = CGRect(x: bounds.minX + margin, y: bottom - 40 - dpadSize, width: dpadSize, height: dpadSize)
            self.addDPad(dpadFrame, opacity)

            let centerY = dpadFrame.midY
            let aCenter = CGPoint(x: bounds.maxX - margin - faceSize / 2, y: centerY - faceSize * 0.38)
            let bCenter = CGPoint(x: aCenter.x - faceSize * 1.22, y: centerY + faceSize * 0.38)
            self.addButton(.b, "B", .circle, CGRect(x: bCenter.x - faceSize / 2, y: bCenter.y - faceSize / 2, width: faceSize, height: faceSize), opacity)
            self.addButton(.a, "A", .circle, CGRect(x: aCenter.x - faceSize / 2, y: aCenter.y - faceSize / 2, width: faceSize, height: faceSize), opacity)

            let pill = CGSize(width: 64, height: 26)
            self.addButton(.select, "SELECT", .pill, CGRect(x: dpadFrame.midX - pill.width / 2, y: bottom - pill.height, width: pill.width, height: pill.height), opacity)
            self.addButton(.start, "START", .pill, CGRect(x: (aCenter.x + bCenter.x) / 2 - pill.width / 2, y: bottom - pill.height, width: pill.width, height: pill.height), opacity)
        }

        self.applyPressedState()
    }

    private func addDPad(_ frame: CGRect, _ opacity: Float)
    {
        let container = CALayer()
        container.frame = frame
        container.opacity = opacity

        let arm = frame.width / 3
        let crossPath = UIBezierPath()
        crossPath.append(UIBezierPath(roundedRect: CGRect(x: arm, y: 0, width: arm, height: frame.height), cornerRadius: arm * 0.22))
        crossPath.append(UIBezierPath(roundedRect: CGRect(x: 0, y: arm, width: frame.width, height: arm), cornerRadius: arm * 0.22))

        let fill = CAGradientLayer()
        fill.frame = container.bounds
        fill.colors = [UIColor(white: 0.30, alpha: 1).cgColor, UIColor(white: 0.16, alpha: 1).cgColor]
        let mask = CAShapeLayer()
        mask.path = crossPath.cgPath
        fill.mask = mask
        container.addSublayer(fill)

        let outline = CAShapeLayer()
        outline.path = crossPath.cgPath
        outline.fillColor = nil
        outline.strokeColor = UIColor(white: 1, alpha: 0.14).cgColor
        outline.lineWidth = 1
        container.addSublayer(outline)

        // Centre dimple
        let dimple = CAShapeLayer()
        dimple.path = UIBezierPath(ovalIn: CGRect(x: frame.width / 2 - arm * 0.22, y: frame.height / 2 - arm * 0.22, width: arm * 0.44, height: arm * 0.44)).cgPath
        dimple.fillColor = UIColor(white: 0.08, alpha: 0.8).cgColor
        container.addSublayer(dimple)

        // Arms: highlight + arrow per direction.
        let arms: [(KeroButtons, CGRect, CGFloat)] = [
            (.up, CGRect(x: arm, y: 0, width: arm, height: arm), 0),
            (.down, CGRect(x: arm, y: arm * 2, width: arm, height: arm), .pi),
            (.left, CGRect(x: 0, y: arm, width: arm, height: arm), -.pi / 2),
            (.right, CGRect(x: arm * 2, y: arm, width: arm, height: arm), .pi / 2),
        ]

        for (button, rect, angle) in arms
        {
            let highlight = CAShapeLayer()
            highlight.path = UIBezierPath(roundedRect: rect, cornerRadius: arm * 0.22).cgPath
            highlight.fillColor = UIColor(white: 1, alpha: 0.22).cgColor
            highlight.opacity = 0
            container.addSublayer(highlight)
            self.dpadArmLayers[button] = highlight

            let arrowSize = arm * 0.28
            let arrow = CAShapeLayer()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -arrowSize / 2))
            path.addLine(to: CGPoint(x: arrowSize / 2, y: arrowSize / 2))
            path.addLine(to: CGPoint(x: -arrowSize / 2, y: arrowSize / 2))
            path.close()
            arrow.path = path.cgPath
            arrow.fillColor = UIColor(white: 1, alpha: 0.45).cgColor
            arrow.position = CGPoint(x: rect.midX, y: rect.midY)
            arrow.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            container.addSublayer(arrow)
        }

        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.45
        container.shadowRadius = 8
        container.shadowOffset = CGSize(width: 0, height: 4)
        container.shadowPath = crossPath.cgPath

        self.layer.addSublayer(container)

        let hitFrame = frame.insetBy(dx: -frame.width * 0.18, dy: -frame.height * 0.18)
        self.controls.append(Control(kind: .dpad, frame: frame, hitFrame: hitFrame, layer: container, highlight: CALayer()))
    }

    private func addButton(_ button: KeroButtons, _ label: String, _ shape: Shape, _ frame: CGRect, _ opacity: Float)
    {
        let container = CALayer()
        container.frame = frame
        container.opacity = opacity

        let path: UIBezierPath
        switch shape
        {
        case .circle: path = UIBezierPath(ovalIn: container.bounds)
        case .pill: path = UIBezierPath(roundedRect: container.bounds, cornerRadius: frame.height / 2)
        case .shoulder: path = UIBezierPath(roundedRect: container.bounds, cornerRadius: frame.height * 0.35)
        }

        let fill = CAGradientLayer()
        fill.frame = container.bounds
        fill.colors = shape == .circle
            ? [UIColor(white: 0.34, alpha: 1).cgColor, UIColor(white: 0.18, alpha: 1).cgColor]
            : [UIColor(white: 0.26, alpha: 1).cgColor, UIColor(white: 0.16, alpha: 1).cgColor]
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        fill.mask = mask
        container.addSublayer(fill)

        let outline = CAShapeLayer()
        outline.path = path.cgPath
        outline.fillColor = nil
        outline.strokeColor = UIColor(white: 1, alpha: 0.15).cgColor
        outline.lineWidth = 1
        container.addSublayer(outline)

        let highlight = CAShapeLayer()
        highlight.path = path.cgPath
        highlight.fillColor = UIColor(white: 1, alpha: 0.25).cgColor
        highlight.opacity = 0
        container.addSublayer(highlight)

        let text = CATextLayer()
        text.string = label
        text.contentsScale = UIScreen.main.scale
        text.alignmentMode = .center
        let fontSize: CGFloat
        switch shape
        {
        case .circle: fontSize = frame.height * 0.36
        case .pill: fontSize = 10
        case .shoulder: fontSize = 16
        }
        text.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        text.fontSize = fontSize
        text.foregroundColor = UIColor(white: 1, alpha: 0.8).cgColor
        text.frame = CGRect(x: 0, y: (frame.height - fontSize * 1.25) / 2, width: frame.width, height: fontSize * 1.3)
        container.addSublayer(text)

        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.45
        container.shadowRadius = 6
        container.shadowOffset = CGSize(width: 0, height: 3)
        container.shadowPath = path.cgPath

        self.layer.addSublayer(container)

        // Generous touch targets; face buttons overlap a little so a thumb between A and B presses both.
        let expansion: CGFloat
        switch shape
        {
        case .circle: expansion = frame.width * 0.32
        case .pill: expansion = 12
        case .shoulder: expansion = 14
        }
        let hitFrame = frame.insetBy(dx: -expansion, dy: -expansion)

        self.controls.append(Control(kind: .button(button, label: label, shape: shape), frame: frame, hitFrame: hitFrame, layer: container, highlight: highlight))
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchButtons[ObjectIdentifier(touch)] = self.buttons(at: touch.location(in: self))
        }
        self.update()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchButtons[ObjectIdentifier(touch)] = self.buttons(at: touch.location(in: self))
        }
        self.update()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchButtons[ObjectIdentifier(touch)] = nil
        }
        self.update()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        self.touchesEnded(touches, with: event)
    }

    private func buttons(at point: CGPoint) -> KeroButtons
    {
        var result: KeroButtons = []

        for control in self.controls where control.hitFrame.contains(point)
        {
            switch control.kind
            {
            case .dpad:
                result.formUnion(self.directions(at: point, in: control.frame))
            case .button(let button, _, let shape):
                if shape == .circle
                {
                    // Circular hit area (expanded), so the corners of the square don't count.
                    let center = CGPoint(x: control.frame.midX, y: control.frame.midY)
                    let radius = control.hitFrame.width / 2
                    if hypot(point.x - center.x, point.y - center.y) <= radius { result.insert(button) }
                }
                else
                {
                    result.insert(button)
                }
            }
        }

        return result
    }

    /// 8-way D-pad: a direction counts when the touch is within 67.5° of it.
    private func directions(at point: CGPoint, in frame: CGRect) -> KeroButtons
    {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        guard hypot(dx, dy) > frame.width * 0.10 else { return [] }

        let angle = Double(atan2(-dy, dx))
        let window = Double.pi * 3 / 8

        func near(_ target: Double) -> Bool
        {
            var delta = abs(angle - target)
            if delta > .pi { delta = 2 * .pi - delta }
            return delta < window
        }

        var result: KeroButtons = []
        if near(0) { result.insert(.right) }
        if near(.pi / 2) { result.insert(.up) }
        if near(.pi) { result.insert(.left) }
        if near(-.pi / 2) { result.insert(.down) }
        return result
    }

    private func update()
    {
        let buttons = self.touchButtons.values.reduce(into: KeroButtons()) { $0.formUnion($1) }
        guard buttons != self.current else { return }

        let newlyPressed = buttons.subtracting(self.current)
        let directions: KeroButtons = [.up, .down, .left, .right]
        if !newlyPressed.subtracting(directions).isEmpty
        {
            self.pressFeedback.impactOccurred()
            self.pressFeedback.prepare()
        }
        else if !newlyPressed.isEmpty
        {
            self.slideFeedback.selectionChanged()
            self.slideFeedback.prepare()
        }

        self.current = buttons
        self.buttonsChanged?(buttons)
        self.applyPressedState()
    }

    private func applyPressedState()
    {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for control in self.controls
        {
            if case .button(let button, _, _) = control.kind
            {
                let pressed = self.current.contains(button)
                control.highlight.opacity = pressed ? 1 : 0
                control.layer.setAffineTransform(pressed ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity)
            }
        }

        for (button, layer) in self.dpadArmLayers
        {
            layer.opacity = self.current.contains(button) ? 1 : 0
        }

        CATransaction.commit()
    }
}
