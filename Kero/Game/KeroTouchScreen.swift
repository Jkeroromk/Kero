//
//  KeroTouchScreen.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  The DS touch screen: one finger, reported in DS pixels (256×192), immediately on touch-down and
//  on every move, and nil when the finger lifts.
//

import SwiftUI
import UIKit

struct KeroTouchScreen: UIViewRepresentable
{
    var onTouch: (CGPoint?) -> Void

    func makeUIView(context: Context) -> KeroTouchScreenView
    {
        let view = KeroTouchScreenView()
        view.onTouch = self.onTouch
        return view
    }

    func updateUIView(_ view: KeroTouchScreenView, context: Context)
    {
        view.onTouch = self.onTouch
    }

    static func dismantleUIView(_ view: KeroTouchScreenView, coordinator: ())
    {
        view.onTouch?(nil)
    }
}

final class KeroTouchScreenView: UIView
{
    static let screenSize = CGSize(width: 256, height: 192)

    var onTouch: ((CGPoint?) -> Void)?

    /// Only the first finger on the screen counts; the DS can't sense more than one.
    private var activeTouch: UITouch?

    override init(frame: CGRect)
    {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        guard self.activeTouch == nil, let touch = touches.first else { return }
        self.activeTouch = touch
        self.report(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        guard let touch = self.activeTouch, touches.contains(touch) else { return }
        self.report(touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        guard let touch = self.activeTouch, touches.contains(touch) else { return }
        self.activeTouch = nil
        self.onTouch?(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        self.touchesEnded(touches, with: event)
    }

    private func report(_ touch: UITouch)
    {
        guard self.bounds.width > 0, self.bounds.height > 0 else { return }

        let location = touch.location(in: self)
        let x = min(max(location.x / self.bounds.width, 0), 1) * (Self.screenSize.width - 1)
        let y = min(max(location.y / self.bounds.height, 0), 1) * (Self.screenSize.height - 1)
        self.onTouch?(CGPoint(x: x.rounded(), y: y.rounded()))
    }
}
