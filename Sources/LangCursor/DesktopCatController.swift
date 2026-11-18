import AppKit
import LangCursorCore

/// Owns a small, click-through floating window, independent of the language badge.
@MainActor
final class DesktopCatController {
    private(set) var isEnabled = true
    private(set) var size: CGFloat = 64 * 0.8

    private var motion = CatMotion(position: .zero)
    private var panel: DesktopCatPanel?
    private var spriteView: DesktopCatView?
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var previousTick: TimeInterval?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var started = false
    private var suspended = false
    private var needs = CatNeeds(now: ProcessInfo.processInfo.systemUptime)
    private var bowl: BowlPanel?
    private var poops: [PoopPanel] = []

    func start() {
        guard !started else { return }
        started = true
        suspended = false
        do {
            spriteView = try DesktopCatView(atlas: DesktopCatAtlas(), size: size)
        } catch {
            started = false
            NSLog("Desktop cat atlas could not be loaded: %@", String(describing: error))
            return
        }
        observeEnvironment()
        monitorMouse()
        resetNearCursor()
        recreatePanel()
        scheduleTick(interval: 1 / 30)
    }

    func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        previousTick = nil
        panel?.close()
        panel = nil
        bowl?.close()
        bowl = nil
        for poop in poops { poop.close() }
        poops.removeAll()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard started else { return }
        if enabled {
            needs.recordActivity(at: ProcessInfo.processInfo.systemUptime)
            resetNearCursor()
            recreatePanel()
            for poop in poops { poop.orderFrontRegardless() }
            scheduleTick(interval: 1 / 30)
        } else {
            timer?.invalidate()
            timer = nil
            previousTick = nil
            panel?.orderOut(nil)
            dismissBowl()
            for poop in poops { poop.orderOut(nil) }
        }
    }

    /// Seconds without cursor movement before the cat fetches its bowl. `0` turns it off.
    func setHungerDelay(_ seconds: TimeInterval) {
        needs.setHungerDelay(seconds, now: ProcessInfo.processInfo.systemUptime)
        dismissBowl()
    }

    /// Seconds between droppings. `0` turns it off.
    func setPoopInterval(_ seconds: TimeInterval) {
        needs.setPoopInterval(seconds, now: ProcessInfo.processInfo.systemUptime)
    }

    func setSize(_ points: CGFloat) {
        size = min(max(points, 40), 96) * 0.8
        spriteView?.resize(to: size)
        panel?.setContentSize(NSSize(width: size, height: size))
        keepOnAvailableScreens()
        render()
    }

    private func resetNearCursor() {
        guard let screen = cursorScreen() else { return }
        motion.reset(position: CatPlacement.target(
            cursor: NSEvent.mouseLocation, screen: screen.visibleFrame,
            catSize: CGSize(width: size, height: size)
        ))
        previousTick = nil
    }

    private func cursorScreen() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
    }

    private func tick() {
        guard started, isEnabled, !suspended, let screen = cursorScreen() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = previousTick.map { min(max(now - $0, 0), 0.1) } ?? 0
        previousTick = now
        let target = errandTarget(on: screen)
        _ = motion.update(deltaTime: delta, target: target)
        let resting = motion.phase != .running && motion.phase != .settling
        // A target closer than the start distance never wakes the cat, so that counts as arrived.
        let arrived = resting && hypot(motion.position.x - target.x, motion.position.y - target.y) <= 20
        needs.update(now: now, catArrived: arrived)
        if needs.shouldPoop(now: now, catResting: resting, poopCount: poops.count) {
            dropPoop(on: screen)
        }
        keepOnAvailableScreens()
        render()

        // Resting needs few wakeups. Short sit clips keep all eight frames at 60 Hz.
        // Grooming runs at 30 Hz; cursor movement immediately restores a 60 Hz sample rate.
        switch motion.phase {
        case .idle: scheduleTick(interval: 1 / 12)
        case .licking, .washing, .stretching: scheduleTick(interval: 1 / 30)
        case .running, .settling: scheduleTick(interval: 1 / 60)
        }
    }

    /// While hungry, the cat first walks to the nearer side edge to pick up its bowl.
    private func errandTarget(on screen: NSScreen) -> CGPoint {
        let catSize = CGSize(width: size, height: size)
        let frame = screen.visibleFrame
        guard needs.errand == .leaving else {
            return CatPlacement.target(cursor: NSEvent.mouseLocation, screen: frame, catSize: catSize)
        }
        let edgeX = motion.position.x < frame.midX ? frame.minX : frame.maxX
        return CatPlacement.clamp(position: CGPoint(x: edgeX, y: motion.position.y),
                                  to: frame, catSize: catSize)
    }

    private func dropPoop(on screen: NSScreen) {
        let poopSize = (size * 0.5).rounded()
        // Behind the cat: a left-facing (mirrored) cat leaves it on its right.
        let behind: CGFloat = motion.pose.mirrored ? 1 : -1
        let spot = CatPlacement.clamp(
            position: CGPoint(x: motion.position.x + behind * size * 0.32,
                              y: motion.position.y - size * 0.32),
            to: screen.visibleFrame, catSize: CGSize(width: poopSize, height: poopSize)
        )
        let poop = PoopPanel(center: spot, size: poopSize)
        poop.onClean = { [weak self] poop in self?.clean(poop) }
        poops.append(poop)
        poop.appear()
        panel?.orderFrontRegardless()
        bowl?.orderFrontRegardless()
    }

    private func clean(_ poop: PoopPanel) {
        poops.removeAll { $0 === poop }
        poop.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            poop.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { poop.close() }
        })
    }

    private func dismissBowl() {
        bowl?.dismiss()
        bowl = nil
    }

    private func renderBowl() {
        guard needs.showsBowl, isEnabled, !suspended else { return }
        let bowlSize = (size * 0.55).rounded()
        if bowl == nil {
            let bowl = BowlPanel(size: bowlSize)
            self.bowl = bowl
            bowl.orderFrontRegardless()
        }
        // Carried at the mouth while walking; set down in front of the paws once it arrives.
        let forward: CGFloat = motion.pose.mirrored ? -1 : 1
        let carried = needs.errand == .returning
        bowl?.move(center: CGPoint(
            x: motion.position.x + forward * size * (carried ? 0.36 : 0.52),
            y: motion.position.y - size * (carried ? 0.12 : 0.30)
        ))
    }

    private func scheduleTick(interval: TimeInterval) {
        guard started, isEnabled, !suspended, spriteView != nil else { return }
        if timer != nil, abs(timerInterval - interval) < 0.0001 { return }
        timer?.invalidate()
        timerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval / 8
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func render() {
        guard let panel, let spriteView else { return }
        spriteView.render(motion.pose)
        let origin = CGPoint(x: motion.position.x - size / 2, y: motion.position.y - size / 2)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        renderBowl()
    }

    private func recreatePanel() {
        guard let spriteView else { return }
        let old = panel
        let panel = DesktopCatPanel(size: size)
        panel.contentView = spriteView
        self.panel = panel
        old?.close()
        render()
        if isEnabled && !suspended {
            panel.orderFrontRegardless()
            bowl?.orderFrontRegardless()
        }
    }

    private func keepOnAvailableScreens() {
        let catSize = CGSize(width: size, height: size)
        guard !NSScreen.screens.contains(where: { $0.frame.contains(motion.position) }) else { return }
        guard let screen = cursorScreen() else { return }
        motion.reset(position: CatPlacement.clamp(
            position: motion.position, to: screen.visibleFrame, catSize: catSize
        ))
        previousTick = nil
    }

    private func monitorMouse() {
        let events: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.cursorMoved() }
            return event
        }
    }

    private func cursorMoved() {
        guard isEnabled, !suspended else { return }
        if needs.recordActivity(at: ProcessInfo.processInfo.systemUptime) { dismissBowl() }
        scheduleTick(interval: 1 / 60)
    }

    private func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspace) { controller in
            controller.recreatePanel()
        }
        observe(NSApplication.didChangeScreenParametersNotification, on: .default) { controller in
            controller.keepOnAvailableScreens()
            controller.recreatePanel()
        }
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                             NSWorkspace.sessionDidResignActiveNotification] {
            observe(notification, on: workspace) { controller in controller.suspend() }
        }
        for notification in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                             NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(notification, on: workspace) { controller in controller.resume() }
        }
    }

    private func observe(
        _ name: Notification.Name, on center: NotificationCenter,
        perform action: @escaping @MainActor (DesktopCatController) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, observer))
    }

    private func suspend() {
        suspended = true
        timer?.invalidate()
        timer = nil
        previousTick = nil
        panel?.orderOut(nil)
        dismissBowl()
        for poop in poops { poop.orderOut(nil) }
    }

    private func resume() {
        suspended = false
        previousTick = nil
        needs.recordActivity(at: ProcessInfo.processInfo.systemUptime)
        if isEnabled { for poop in poops { poop.orderFrontRegardless() } }
        keepOnAvailableScreens()
        recreatePanel()
        scheduleTick(interval: 1 / 30)
    }
}

@MainActor
private final class DesktopCatPanel: NSPanel {
    init(size: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        // Stay above ordinary app windows while forwarding clicks to the app underneath.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
