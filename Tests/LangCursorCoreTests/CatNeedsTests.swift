import Testing
@testable import LangCursorCore

@Suite struct CatNeedsTests {
    @Test func getsHungryOnlyAfterTheCursorStaysStillForTheDelay() {
        var needs = CatNeeds(now: 0, hungerDelay: 60)
        needs.update(now: 59.9, catArrived: true)
        #expect(needs.errand == .none)
        needs.update(now: 60, catArrived: false)
        #expect(needs.errand == .leaving)
        #expect(!needs.showsBowl)
    }

    @Test func movementRestartsTheHungerCountdown() {
        var needs = CatNeeds(now: 0, hungerDelay: 60)
        needs.recordActivity(at: 50)
        needs.update(now: 100, catArrived: false)
        #expect(needs.errand == .none)
        needs.update(now: 110, catArrived: false)
        #expect(needs.errand == .leaving)
    }

    @Test func fetchesTheBowlThenWaitsBesideIt() {
        var needs = CatNeeds(now: 0, hungerDelay: 30)
        needs.update(now: 30, catArrived: false)
        needs.update(now: 31, catArrived: false)
        #expect(needs.errand == .leaving)
        needs.update(now: 35, catArrived: true)
        #expect(needs.errand == .returning)
        #expect(needs.showsBowl)
        needs.update(now: 36, catArrived: false)
        #expect(needs.errand == .returning)
        needs.update(now: 40, catArrived: true)
        #expect(needs.errand == .waiting)
        needs.update(now: 400, catArrived: true)
        #expect(needs.errand == .waiting)
        #expect(needs.showsBowl)
    }

    @Test func movementEndsTheErrandAndReportsIt() {
        var needs = CatNeeds(now: 0, hungerDelay: 30)
        do { let result = needs.recordActivity(at: 1); #expect(!result) }
        needs.update(now: 31, catArrived: false)
        needs.update(now: 32, catArrived: true)
        do { let result = needs.recordActivity(at: 33); #expect(result) }
        #expect(needs.errand == .none)
        #expect(!needs.showsBowl)
    }

    @Test func zeroDelayDisablesHunger() {
        var needs = CatNeeds(now: 0, hungerDelay: 0)
        needs.update(now: 10_000, catArrived: true)
        #expect(needs.errand == .none)
    }

    @Test func changingTheDelayCountsFromNow() {
        var needs = CatNeeds(now: 0, hungerDelay: 600)
        needs.setHungerDelay(30, now: 100)
        needs.update(now: 129, catArrived: false)
        #expect(needs.errand == .none)
        needs.update(now: 130, catArrived: false)
        #expect(needs.errand == .leaving)
    }

    @Test func poopsOncePerIntervalWhileResting() {
        var needs = CatNeeds(now: 0, hungerDelay: 0, poopInterval: 120)
        do { let result = needs.shouldPoop(now: 119, catResting: true, poopCount: 0); #expect(!result) }
        do { let result = needs.shouldPoop(now: 120, catResting: true, poopCount: 0); #expect(result) }
        do { let result = needs.shouldPoop(now: 121, catResting: true, poopCount: 1); #expect(!result) }
        do { let result = needs.shouldPoop(now: 240, catResting: true, poopCount: 1); #expect(result) }
    }

    @Test func dueDroppingWaitsUntilTheCatRestsAndThereIsRoom() {
        var needs = CatNeeds(now: 0, hungerDelay: 0, poopInterval: 60)
        do { let result = needs.shouldPoop(now: 70, catResting: false, poopCount: 0); #expect(!result) }
        do { let result = needs.shouldPoop(now: 71, catResting: true, poopCount: CatNeeds.maxPoops); #expect(!result) }
        do { let result = needs.shouldPoop(now: 72, catResting: true, poopCount: CatNeeds.maxPoops - 1); #expect(result) }
    }

    @Test func doesNotPoopDuringAnErrand() {
        var needs = CatNeeds(now: 0, hungerDelay: 10, poopInterval: 10)
        needs.update(now: 10, catArrived: false)
        do { let result = needs.shouldPoop(now: 20, catResting: true, poopCount: 0); #expect(!result) }
        needs.recordActivity(at: 21)
        do { let result = needs.shouldPoop(now: 21, catResting: true, poopCount: 0); #expect(result) }
    }

    @Test func zeroIntervalDisablesPooping() {
        var needs = CatNeeds(now: 0, poopInterval: 300)
        needs.setPoopInterval(0, now: 10)
        do { let result = needs.shouldPoop(now: 10_000, catResting: true, poopCount: 0); #expect(!result) }
    }
}
