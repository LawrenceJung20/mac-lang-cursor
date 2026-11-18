import Foundation

/// Hunger and litter timing for the desktop cat, independent of AppKit.
/// Times are monotonic seconds (`ProcessInfo.systemUptime`). A delay of `0` turns the need off.
public struct CatNeeds: Sendable {
    /// The bowl-fetching errand that starts after the cursor has been still for `hungerDelay`.
    public enum Errand: Equatable, Sendable {
        /// Following the cursor as usual.
        case none
        /// Walking to the screen edge to pick up the bowl.
        case leaving
        /// Carrying the bowl back to the cursor.
        case returning
        /// Sitting next to the bowl until the cursor moves again.
        case waiting
    }

    public static let maxPoops = 5

    public private(set) var errand: Errand = .none
    public private(set) var hungerDelay: TimeInterval
    public private(set) var poopInterval: TimeInterval
    private var lastActivity: TimeInterval
    private var nextPoop: TimeInterval

    public init(now: TimeInterval, hungerDelay: TimeInterval = 60, poopInterval: TimeInterval = 300) {
        self.hungerDelay = max(0, hungerDelay)
        self.poopInterval = max(0, poopInterval)
        lastActivity = now
        nextPoop = now + self.poopInterval
    }

    /// The bowl is visible while it is carried and after it has been put down.
    public var showsBowl: Bool { errand == .returning || errand == .waiting }

    /// Cursor movement. Ends any errand; returns `true` when one was interrupted.
    @discardableResult
    public mutating func recordActivity(at now: TimeInterval) -> Bool {
        lastActivity = now
        guard errand != .none else { return false }
        errand = .none
        return true
    }

    /// Advances the errand. `catArrived` means the cat is resting at the current errand target.
    public mutating func update(now: TimeInterval, catArrived: Bool) {
        switch errand {
        case .none where hungerDelay > 0 && now - lastActivity >= hungerDelay:
            errand = .leaving
        case .leaving where catArrived:
            errand = .returning
        case .returning where catArrived:
            errand = .waiting
        default:
            break
        }
    }

    /// `true` once per interval, as soon as the cat is resting, not on an errand, and the
    /// screen has room for another dropping. A due dropping waits for those conditions.
    public mutating func shouldPoop(now: TimeInterval, catResting: Bool, poopCount: Int) -> Bool {
        guard poopInterval > 0, now >= nextPoop,
              catResting, errand == .none, poopCount < Self.maxPoops else { return false }
        nextPoop = now + poopInterval
        return true
    }

    public mutating func setHungerDelay(_ delay: TimeInterval, now: TimeInterval) {
        hungerDelay = max(0, delay)
        // A new setting counts from now, so shortening it never fires instantly.
        recordActivity(at: now)
    }

    public mutating func setPoopInterval(_ interval: TimeInterval, now: TimeInterval) {
        poopInterval = max(0, interval)
        nextPoop = now + poopInterval
    }
}
