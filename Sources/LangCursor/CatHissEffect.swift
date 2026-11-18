import AppKit

/// The cat's angry reaction when clicked: three claw slashes in front of it and a speech
/// bubble saying "hiss" in some language. Click-through, plays once, then closes itself.
@MainActor
final class HissPanel: NSPanel {
    static let duration: CFTimeInterval = 1.6

    private let effectView: NSView
    private let catPoint: CGPoint
    private let catSize: CGFloat
    private let facingLeft: Bool
    private let text: String

    init(catCenter: CGPoint, catSize: CGFloat, facingLeft: Bool, text: String) {
        let width = catSize * 4.4
        let height = catSize * 3.2
        // The cat sits low in the middle; the bubble gets the room above it.
        catPoint = CGPoint(x: width / 2, y: catSize * 1.0)
        self.catSize = catSize
        self.facingLeft = facingLeft
        self.text = text
        effectView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        super.init(
            contentRect: NSRect(x: catCenter.x - catPoint.x, y: catCenter.y - catPoint.y,
                                width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = effectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func play(completion: @escaping @MainActor () -> Void) {
        guard let root = effectView.layer else { return }
        orderFrontRegardless()
        let scale = screen?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        addClawMarks(to: root)
        addBubble(to: root, scale: scale)
        CATransaction.commit()
    }

    private func addClawMarks(to root: CALayer) {
        let forward: CGFloat = facingLeft ? -1 : 1
        let center = CGPoint(x: catPoint.x + forward * catSize * 0.62, y: catPoint.y + catSize * 0.05)
        let length = catSize * 0.6
        let gap = catSize * 0.15
        let now = CACurrentMediaTime()
        for index in 0..<3 {
            let offset = CGFloat(index - 1) * gap
            // Slashes run from upper-forward to lower-back, like a downward swipe of the paw.
            let start = CGPoint(x: center.x + forward * (length * 0.32 + offset), y: center.y + length / 2 - offset * 0.3)
            let end = CGPoint(x: center.x - forward * (length * 0.32 - offset), y: center.y - length / 2 - offset * 0.3)
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 + forward * catSize * 0.08,
                                                        y: (start.y + end.y) / 2))
            for (color, width) in [(NSColor.white.withAlphaComponent(0.9), catSize * 0.11),
                                   (NSColor(calibratedRed: 0.86, green: 0.1, blue: 0.16, alpha: 1), catSize * 0.055)] {
                let slash = CAShapeLayer()
                slash.path = path
                slash.fillColor = nil
                slash.strokeColor = color.cgColor
                slash.lineWidth = max(1.5, width)
                slash.lineCap = .round
                slash.opacity = 0

                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0
                draw.toValue = 1
                draw.duration = 0.12
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1, 1, 0]
                fade.keyTimes = [0, 0.55, 1]
                let group = CAAnimationGroup()
                group.animations = [draw, fade]
                group.duration = 0.75
                // One slash after another, as the paw sweeps across.
                group.beginTime = now + 0.08 + Double(index) * 0.05
                group.fillMode = .backwards
                slash.add(group, forKey: "slash")
                root.addSublayer(slash)
            }
        }
    }

    private func addBubble(to root: CALayer, scale: CGFloat) {
        let font = NSFont.systemFont(ofSize: max(11, catSize * 0.3), weight: .heavy)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(calibratedRed: 0.75, green: 0.08, blue: 0.12, alpha: 1),
        ])
        let textSize = attributed.size()
        let padding = CGSize(width: catSize * 0.2, height: catSize * 0.1)
        let bubbleSize = CGSize(width: ceil(textSize.width + padding.width * 2),
                                height: ceil(textSize.height + padding.height * 2))
        let tail = catSize * 0.2
        let bounds = effectView.bounds
        let forward: CGFloat = facingLeft ? -1 : 1
        let x = min(max(catPoint.x + forward * catSize * 0.25 - bubbleSize.width / 2, 2),
                    bounds.width - bubbleSize.width - 2)
        let y = min(catPoint.y + catSize * 0.45 + tail, bounds.height - bubbleSize.height - 2)
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: bubbleSize)

        // The bubble layer is anchored at its tail tip, so it pops out of the cat's head.
        let tip = CGPoint(x: catPoint.x + forward * catSize * 0.05, y: catPoint.y + catSize * 0.3)
        let bubble = CAShapeLayer()
        bubble.bounds = bounds
        bubble.anchorPoint = CGPoint(x: tip.x / bounds.width, y: tip.y / bounds.height)
        bubble.position = tip
        // One continuous outline (body plus tail), so no seam shows where the tail joins.
        let radius = bubbleSize.height / 2.2
        let halfTail = tail * 0.45
        let baseX = min(max(tip.x, frame.minX + radius + halfTail), frame.maxX - radius - halfTail)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: baseX + halfTail, y: frame.minY))
        path.addArc(tangent1End: CGPoint(x: frame.maxX, y: frame.minY),
                    tangent2End: CGPoint(x: frame.maxX, y: frame.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: frame.maxX, y: frame.maxY),
                    tangent2End: CGPoint(x: frame.minX, y: frame.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: frame.minX, y: frame.maxY),
                    tangent2End: CGPoint(x: frame.minX, y: frame.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: frame.minX, y: frame.minY),
                    tangent2End: CGPoint(x: frame.maxX, y: frame.minY), radius: radius)
        path.addLine(to: CGPoint(x: baseX - halfTail, y: frame.minY))
        path.addLine(to: tip)
        path.closeSubpath()
        bubble.path = path
        bubble.fillColor = NSColor.white.cgColor
        bubble.strokeColor = NSColor(calibratedWhite: 0.15, alpha: 1).cgColor
        bubble.lineWidth = max(1.2, catSize * 0.035)
        bubble.lineJoin = .round

        let label = CATextLayer()
        label.string = attributed
        label.contentsScale = scale
        label.alignmentMode = .center
        label.frame = CGRect(x: frame.minX, y: frame.minY + padding.height - 1,
                             width: frame.width, height: textSize.height + 2)
        bubble.addSublayer(label)

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.2, 1.18, 0.94, 1]
        pop.keyTimes = [0, 0.45, 0.75, 1]
        pop.duration = 0.28
        // An angry little shudder while it is shown.
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, 0.07, -0.07, 0.05, -0.05, 0]
        shake.beginTime = 0.28
        shake.duration = 0.35
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.8, 1]
        fade.duration = Self.duration
        let group = CAAnimationGroup()
        group.animations = [pop, shake, fade]
        group.duration = Self.duration
        bubble.opacity = 0
        bubble.add(group, forKey: "bubble")
        root.addSublayer(bubble)
    }
}
