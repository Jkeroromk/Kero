//
//  KeroTouchController.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  On-screen controller built on raw UIKit multitouch (not SwiftUI gestures), so presses
//  register immediately, several buttons can be held at once, and a thumb can slide
//  across the D-pad or between A and B. Positions come from KeroConsoleLayout.
//

import SwiftUI
import UIKit

import KeroEngine

struct KeroTouchController: UIViewRepresentable
{
    var layout: KeroConsoleLayout
    var system: KeroSystem
    var onChange: (KeroButtons) -> Void

    func makeUIView(context: Context) -> KeroTouchControllerView
    {
        let view = KeroTouchControllerView()
        view.buttonsChanged = self.onChange
        view.configure(layout: self.layout, system: self.system)
        return view
    }

    func updateUIView(_ view: KeroTouchControllerView, context: Context)
    {
        view.buttonsChanged = self.onChange
        view.configure(layout: self.layout, system: self.system)
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
        case button(KeroButtons, shape: Shape)
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

    private var layout = KeroConsoleLayout(style: .screenOnly, size: .zero)
    private var system: KeroSystem = .gameBoyAdvance
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

    func configure(layout: KeroConsoleLayout, system: KeroSystem)
    {
        guard layout != self.layout || system != self.system else { return }

        self.layout = layout
        self.system = system
        self.rebuildControls()
    }

    func releaseAll()
    {
        self.touchButtons.removeAll()
        self.update()
    }

    // MARK: Hit testing

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool
    {
        // Only the controls take touches; everything else (home button, picture) passes through.
        return self.controls.contains { $0.hitFrame.contains(point) }
    }

    // MARK: Skin

    private var isOverlay: Bool { self.layout.style == .overlay }

    private var faceColors: (top: UIColor, bottom: UIColor) {
        switch self.system
        {
        case .gameBoy, .gameBoyColor:
            return (UIColor(red: 0.62, green: 0.20, blue: 0.40, alpha: 1), UIColor(red: 0.42, green: 0.11, blue: 0.27, alpha: 1))
        case .nes:
            return (UIColor(red: 0.66, green: 0.20, blue: 0.20, alpha: 1), UIColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1))
        case .snes:
            return (UIColor(red: 0.48, green: 0.44, blue: 0.66, alpha: 1), UIColor(red: 0.32, green: 0.29, blue: 0.48, alpha: 1))
        default:
            return (UIColor(white: 0.32, alpha: 1), UIColor(white: 0.17, alpha: 1))
        }
    }

    private func rebuildControls()
    {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        self.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.controls.removeAll()
        self.dpadArmLayers.removeAll()

        guard self.layout.hasControls else { return }

        let opacity: Float = self.isOverlay ? 0.55 : 1.0

        if !self.isOverlay
        {
            self.addWells()
        }

        if !self.layout.l.isEmpty { self.addButton(.l, "L", .shoulder, self.layout.l, opacity) }
        if !self.layout.r.isEmpty { self.addButton(.r, "R", .shoulder, self.layout.r, opacity) }
        self.addDPad(self.layout.dpad, opacity)
        self.addButton(.b, "B", .circle, self.layout.b, opacity)
        self.addButton(.a, "A", .circle, self.layout.a, opacity)
        self.addButton(.select, "SELECT", .pill, self.layout.select, opacity)
        self.addButton(.start, "START", .pill, self.layout.start, opacity)

        self.applyPressedState()
    }

    /// Recessed areas the D-pad and face buttons sit in, like a real console shell.
    private func addWells()
    {
        let dpadWell = CAShapeLayer()
        let dpadRect = self.layout.dpad.insetBy(dx: -self.layout.dpad.width * 0.07, dy: -self.layout.dpad.height * 0.07)
        dpadWell.path = UIBezierPath(ovalIn: dpadRect).cgPath
        dpadWell.fillColor = UIColor(white: 0, alpha: 0.28).cgColor
        dpadWell.strokeColor = UIColor(white: 1, alpha: 0.05).cgColor
        dpadWell.lineWidth = 1
        self.layer.addSublayer(dpadWell)

        // A capsule along the line from B to A.
        let a = CGPoint(x: self.layout.a.midX, y: self.layout.a.midY)
        let b = CGPoint(x: self.layout.b.midX, y: self.layout.b.midY)
        let size = self.layout.a.width
        let length = hypot(a.x - b.x, a.y - b.y) + size * 1.28
        let thickness = size * 1.28

        let faceWell = CAShapeLayer()
        faceWell.bounds = CGRect(x: 0, y: 0, width: length, height: thickness)
        faceWell.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        faceWell.path = UIBezierPath(roundedRect: faceWell.bounds, cornerRadius: thickness / 2).cgPath
        faceWell.fillColor = UIColor(white: 0, alpha: 0.28).cgColor
        faceWell.strokeColor = UIColor(white: 1, alpha: 0.05).cgColor
        faceWell.lineWidth = 1
        faceWell.setAffineTransform(CGAffineTransform(rotationAngle: atan2(a.y - b.y, a.x - b.x)))
        self.layer.addSublayer(faceWell)
    }

    private func addDPad(_ frame: CGRect, _ opacity: Float)
    {
        guard frame.width > 0 else { return }

        let container = CALayer()
        container.frame = frame
        container.opacity = opacity

        let arm = frame.width / 3
        let crossPath = UIBezierPath()
        crossPath.append(UIBezierPath(roundedRect: CGRect(x: arm, y: 0, width: arm, height: frame.height), cornerRadius: arm * 0.2))
        crossPath.append(UIBezierPath(roundedRect: CGRect(x: 0, y: arm, width: frame.width, height: arm), cornerRadius: arm * 0.2))

        let fill = CAGradientLayer()
        fill.frame = container.bounds
        fill.colors = [UIColor(white: 0.24, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor]
        let mask = CAShapeLayer()
        mask.path = crossPath.cgPath
        fill.mask = mask
        container.addSublayer(fill)

        let outline = CAShapeLayer()
        outline.path = crossPath.cgPath
        outline.fillColor = nil
        outline.strokeColor = UIColor(white: 1, alpha: 0.12).cgColor
        outline.lineWidth = 1
        container.addSublayer(outline)

        // Centre dimple
        let dimple = CAShapeLayer()
        dimple.path = UIBezierPath(ovalIn: CGRect(x: frame.width / 2 - arm * 0.24, y: frame.height / 2 - arm * 0.24, width: arm * 0.48, height: arm * 0.48)).cgPath
        dimple.fillColor = UIColor(white: 0.06, alpha: 0.9).cgColor
        container.addSublayer(dimple)

        let arms: [(KeroButtons, CGRect, CGFloat)] = [
            (.up, CGRect(x: arm, y: 0, width: arm, height: arm), 0),
            (.down, CGRect(x: arm, y: arm * 2, width: arm, height: arm), .pi),
            (.left, CGRect(x: 0, y: arm, width: arm, height: arm), -.pi / 2),
            (.right, CGRect(x: arm * 2, y: arm, width: arm, height: arm), .pi / 2),
        ]

        for (button, rect, angle) in arms
        {
            let highlight = CAShapeLayer()
            highlight.path = UIBezierPath(roundedRect: rect, cornerRadius: arm * 0.2).cgPath
            highlight.fillColor = UIColor(white: 1, alpha: 0.2).cgColor
            highlight.opacity = 0
            container.addSublayer(highlight)
            self.dpadArmLayers[button] = highlight

            let arrowSize = arm * 0.26
            let arrow = CAShapeLayer()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -arrowSize / 2))
            path.addLine(to: CGPoint(x: arrowSize / 2, y: arrowSize / 2))
            path.addLine(to: CGPoint(x: -arrowSize / 2, y: arrowSize / 2))
            path.close()
            arrow.path = path.cgPath
            arrow.fillColor = UIColor(white: 1, alpha: 0.35).cgColor
            arrow.position = CGPoint(x: rect.midX, y: rect.midY)
            arrow.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            container.addSublayer(arrow)
        }

        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.5
        container.shadowRadius = 6
        container.shadowOffset = CGSize(width: 0, height: 3)
        container.shadowPath = crossPath.cgPath

        self.layer.addSublayer(container)

        let hitFrame = frame.insetBy(dx: -frame.width * 0.18, dy: -frame.height * 0.18)
        self.controls.append(Control(kind: .dpad, frame: frame, hitFrame: hitFrame, layer: container, highlight: CALayer()))
    }

    private func addButton(_ button: KeroButtons, _ label: String, _ shape: Shape, _ frame: CGRect, _ opacity: Float)
    {
        guard frame.width > 0 else { return }

        let container = CALayer()
        container.frame = frame
        container.opacity = opacity

        let path: UIBezierPath
        switch shape
        {
        case .circle: path = UIBezierPath(ovalIn: container.bounds)
        case .pill: path = UIBezierPath(roundedRect: container.bounds, cornerRadius: frame.height / 2)
        case .shoulder: path = UIBezierPath(roundedRect: container.bounds, cornerRadius: frame.height * 0.4)
        }

        let fill = CAGradientLayer()
        fill.frame = container.bounds
        switch shape
        {
        case .circle:
            let colors = self.faceColors
            fill.colors = [colors.top.cgColor, colors.bottom.cgColor]
        case .pill, .shoulder:
            fill.colors = [UIColor(white: 0.22, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor]
        }
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        fill.mask = mask
        container.addSublayer(fill)

        // Top rim light so buttons read as raised.
        let rim = CAShapeLayer()
        rim.path = path.cgPath
        rim.fillColor = nil
        rim.strokeColor = UIColor(white: 1, alpha: 0.14).cgColor
        rim.lineWidth = 1
        container.addSublayer(rim)

        let highlight = CAShapeLayer()
        highlight.path = path.cgPath
        highlight.fillColor = UIColor(white: 1, alpha: 0.22).cgColor
        highlight.opacity = 0
        container.addSublayer(highlight)

        let text = CATextLayer()
        text.string = label
        text.contentsScale = self.traitCollection.displayScale > 0 ? self.traitCollection.displayScale : 3
        text.alignmentMode = .center
        let fontSize: CGFloat
        switch shape
        {
        case .circle: fontSize = frame.height * 0.36
        case .pill: fontSize = 10
        case .shoulder: fontSize = 15
        }
        text.font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        text.fontSize = fontSize
        text.foregroundColor = UIColor(white: 1, alpha: 0.78).cgColor
        text.frame = CGRect(x: 0, y: (frame.height - fontSize * 1.25) / 2, width: frame.width, height: fontSize * 1.3)
        container.addSublayer(text)

        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.5
        container.shadowRadius = 5
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

        self.controls.append(Control(kind: .button(button, shape: shape), frame: frame, hitFrame: hitFrame, layer: container, highlight: highlight))
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
            case .button(let button, let shape):
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
            if case .button(let button, _) = control.kind
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
