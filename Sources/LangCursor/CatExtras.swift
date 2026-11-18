import AppKit

/// A dropping left by the desktop cat. Unlike the cat, it takes clicks: one click cleans it up.
@MainActor
final class PoopPanel: NSPanel {
    var onClean: ((PoopPanel) -> Void)?
    private let flies: FliesPanel

    init(center: CGPoint, size: CGFloat) {
        flies = FliesPanel(poopCenter: center, poopSize: size)
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
        flies.alphaValue = 0
        orderFrontRegardless()
        flies.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            animator().alphaValue = 1
            flies.animator().alphaValue = 1
        }
    }

    /// Fades the dropping and its flies out, then closes both.
    func fadeAway() {
        ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
            flies.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        flies.orderFrontRegardless()
    }

    override func orderOut(_ sender: Any?) {
        flies.orderOut(sender)
        super.orderOut(sender)
    }

    override func close() {
        flies.close()
        super.close()
    }
}

/// Two flies circling over a dropping. Animated by Core Animation, so they cost no app ticks.
@MainActor
private final class FliesPanel: NSPanel {
    init(poopCenter: CGPoint, poopSize: CGFloat) {
        let width = poopSize * 2
        let height = poopSize * 1.6
        super.init(
            contentRect: NSRect(x: poopCenter.x - width / 2, y: poopCenter.y - poopSize * 0.35,
                                width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        contentView = FliesView(frame: NSRect(x: 0, y: 0, width: width, height: height), poopSize: poopSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class FliesView: NSView {
    init(frame: NSRect, poopSize: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        let center = CGPoint(x: frame.width / 2, y: frame.height * 0.62)
        let orbit = CGSize(width: frame.width * 0.32, height: frame.height * 0.16)
        let flySize = max(5, poopSize * 0.26)
        // Different speeds and directions keep the pair from moving in lockstep.
        addFly(center: center, orbit: orbit, size: flySize, duration: 1.7, clockwise: false, offset: 0)
        addFly(center: CGPoint(x: center.x, y: center.y + orbit.height * 0.6),
               orbit: CGSize(width: orbit.width * 0.7, height: orbit.height * 0.8),
               size: flySize * 0.9, duration: 1.2, clockwise: true, offset: 0.4)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    private func addFly(center: CGPoint, orbit: CGSize, size: CGFloat,
                        duration: CFTimeInterval, clockwise: Bool, offset: CFTimeInterval) {
        let fly = CALayer()
        fly.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        fly.position = center

        // Two pale wings that flutter, behind a dark body.
        for side in [-1.0, 1.0] {
            let wing = CALayer()
            wing.bounds = CGRect(x: 0, y: 0, width: size * 0.5, height: size * 0.36)
            wing.position = CGPoint(x: size / 2 + CGFloat(side) * size * 0.2, y: size * 0.66)
            wing.cornerRadius = size * 0.18
            wing.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 0.85).cgColor
            let flutter = CABasicAnimation(keyPath: "opacity")
            flutter.fromValue = 1
            flutter.toValue = 0.25
            flutter.duration = 0.05
            flutter.autoreverses = true
            flutter.repeatCount = .infinity
            wing.add(flutter, forKey: "flutter")
            fly.addSublayer(wing)
        }
        let body = CALayer()
        body.bounds = CGRect(x: 0, y: 0, width: size * 0.42, height: size * 0.36)
        body.position = CGPoint(x: size / 2, y: size * 0.42)
        body.cornerRadius = size * 0.18
        body.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        fly.addSublayer(body)

        let rect = CGRect(x: center.x - orbit.width, y: center.y - orbit.height,
                          width: orbit.width * 2, height: orbit.height * 2)
        var flip = CGAffineTransform(translationX: center.x * 2, y: 0).scaledBy(x: -1, y: 1)
        let path = clockwise ? CGPath(ellipseIn: rect, transform: &flip) : CGPath(ellipseIn: rect, transform: nil)
        let circling = CAKeyframeAnimation(keyPath: "position")
        circling.path = path
        circling.duration = duration
        circling.calculationMode = .paced
        circling.repeatCount = .infinity
        circling.timeOffset = offset
        fly.add(circling, forKey: "circling")

        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -size * 0.4
        bob.toValue = size * 0.4
        bob.duration = duration / 3
        bob.autoreverses = true
        bob.repeatCount = .infinity
        fly.add(bob, forKey: "bob")

        layer?.addSublayer(fly)
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
    var onClick: (() -> Void)?
    private let bowlView: BowlView

    /// Remaining food from 0 (empty) to 1 (full).
    var food: Double = 0 {
        didSet { if bowlView.food != food { bowlView.food = food } }
    }

    /// Only an empty, set-down bowl takes a click; otherwise clicks pass through.
    var acceptsFood = false {
        didSet {
            ignoresMouseEvents = !acceptsFood
            bowlView.clickable = acceptsFood
        }
    }

    init(size: CGFloat) {
        bowlView = BowlView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        bowlView.onClick = { [weak self] in self?.onClick?() }
        contentView = bowlView
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
    var onClick: (() -> Void)?
    var clickable = false
    var food: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        if clickable { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if clickable { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height

        // Kibble heaped above the rim, eaten from the top of the heap down.
        NSColor(calibratedRed: 0.55, green: 0.33, blue: 0.16, alpha: 1).setFill()
        let kibble: [(CGFloat, CGFloat)] = [(0.30, 0.50), (0.48, 0.52), (0.64, 0.50), (0.38, 0.56),
                                            (0.56, 0.57), (0.46, 0.61), (0.60, 0.63), (0.36, 0.62)]
        let pieces = Int((food * Double(kibble.count)).rounded(.up))
        for (x, y) in kibble.prefix(pieces) {
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
