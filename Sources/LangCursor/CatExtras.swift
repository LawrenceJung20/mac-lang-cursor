import AppKit

/// A dropping left by the desktop cat. Unlike the cat, it takes clicks: one click cleans it up.
@MainActor
final class PoopPanel: NSPanel {
    var onClean: ((PoopPanel) -> Void)?

    init(center: CGPoint, size: CGFloat) {
        super.init(
            contentRect: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        // Just under the cat, so it walks over its own droppings.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        ignoresMouseEvents = false
        let view = PoopView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.onClick = { [weak self] in
            guard let self else { return }
            onClean?(self)
        }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func appear() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            animator().alphaValue = 1
        }
    }
}

@MainActor
private final class PoopView: NSView {
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.systemFont(ofSize: bounds.height * 0.78)
        let text = NSAttributedString(string: "💩", attributes: [.font: font])
        let textSize = text.size()
        text.draw(at: CGPoint(x: (bounds.width - textSize.width) / 2,
                              y: (bounds.height - textSize.height) / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// The food bowl the hungry cat carries in its mouth and sets down by the cursor.
@MainActor
final class BowlPanel: NSPanel {
    init(size: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        contentView = BowlView(frame: NSRect(x: 0, y: 0, width: size, height: size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func move(center: CGPoint) {
        let origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        if frame.origin != origin { setFrameOrigin(origin) }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        })
    }
}

@MainActor
private final class BowlView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height

        // Kibble heaped above the rim.
        NSColor(calibratedRed: 0.55, green: 0.33, blue: 0.16, alpha: 1).setFill()
        for (x, y) in [(0.30, 0.56), (0.42, 0.62), (0.55, 0.60), (0.67, 0.55), (0.48, 0.52), (0.36, 0.50), (0.61, 0.49)] {
            NSBezierPath(ovalIn: NSRect(x: w * x - w * 0.07, y: h * y - h * 0.06,
                                        width: w * 0.14, height: h * 0.12)).fill()
        }

        // Bowl body: a wide top tapering to a flat foot.
        let body = NSBezierPath()
        body.move(to: CGPoint(x: w * 0.06, y: h * 0.48))
        body.line(to: CGPoint(x: w * 0.94, y: h * 0.48))
        body.curve(to: CGPoint(x: w * 0.74, y: h * 0.14),
                   controlPoint1: CGPoint(x: w * 0.92, y: h * 0.30),
                   controlPoint2: CGPoint(x: w * 0.84, y: h * 0.16))
        body.line(to: CGPoint(x: w * 0.26, y: h * 0.14))
        body.curve(to: CGPoint(x: w * 0.06, y: h * 0.48),
                   controlPoint1: CGPoint(x: w * 0.16, y: h * 0.16),
                   controlPoint2: CGPoint(x: w * 0.08, y: h * 0.30))
        body.close()
        NSColor(calibratedRed: 0.93, green: 0.36, blue: 0.40, alpha: 1).setFill()
        body.fill()
        NSColor(calibratedRed: 0.62, green: 0.18, blue: 0.22, alpha: 1).setStroke()
        body.lineWidth = max(1, w * 0.03)
        body.stroke()

        // Rim highlight.
        let rim = NSBezierPath(ovalIn: NSRect(x: w * 0.06, y: h * 0.42, width: w * 0.88, height: h * 0.12))
        NSColor(calibratedRed: 1, green: 0.62, blue: 0.64, alpha: 1).setFill()
        rim.fill()
        rim.stroke()

        // A small paw print on the side.
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: w * 0.44, y: h * 0.22, width: w * 0.12, height: h * 0.10)).fill()
        for x in [0.40, 0.48, 0.56] {
            NSBezierPath(ovalIn: NSRect(x: w * x, y: h * 0.33, width: w * 0.05, height: h * 0.05)).fill()
        }
    }
}

@MainActor
private func configureFloating(_ panel: NSPanel) {
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isExcludedFromWindowsMenu = true
}
