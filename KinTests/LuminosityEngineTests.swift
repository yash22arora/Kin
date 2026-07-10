import XCTest
@testable import Kin

/// These tests encode the product's emotional contract, not just math.
/// If a test here fails, the app's feeling is broken — treat as P0.
final class LuminosityEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    // MARK: Contract: warmth

    func testFreshMomentGlowsBright() {
        let l = LuminosityEngine.luminosity(momentDates: [daysAgo(0)], orbit: .weekly, now: now)
        XCTAssertGreaterThan(l, 0.7, "A moment logged today should visibly glow")
    }

    func testSeveralRecentMomentsApproachFullGlow() {
        let dates = [daysAgo(0), daysAgo(1), daysAgo(2), daysAgo(4), daysAgo(6)]
        let l = LuminosityEngine.luminosity(momentDates: dates, orbit: .weekly, now: now)
        XCTAssertGreaterThan(l, 0.9)
        XCTAssertLessThanOrEqual(l, 1.0, "Glow can never be gamed past full")
    }

    // MARK: Contract: never guilt

    func testStarNeverGoesBelowFloor() {
        let l = LuminosityEngine.luminosity(momentDates: [daysAgo(1000)], orbit: .mostDays, now: now)
        XCTAssertGreaterThanOrEqual(l, LuminosityEngine.floorGlow,
            "Stars soften, they never die — the anti-guilt guarantee")
    }

    func testNewbornStarHasGentleGlow() {
        let l = LuminosityEngine.luminosity(momentDates: [], orbit: .weekly, now: now)
        XCTAssertEqual(l, LuminosityEngine.newbornGlow, accuracy: 0.001)
    }

    // MARK: Contract: orbits kill false guilt

    func testRareFriendStaysBrightAfterTwoMonths() {
        let l = LuminosityEngine.luminosity(momentDates: [daysAgo(60)], orbit: .rarely, now: now)
        XCTAssertGreaterThan(l, 0.6,
            "A twice-a-year friend at 2 months of silence is still bright")
    }

    func testWeeklyFriendSoftensAfterThreeWeeks() {
        let fresh = LuminosityEngine.luminosity(momentDates: [daysAgo(0)], orbit: .weekly, now: now)
        let stale = LuminosityEngine.luminosity(momentDates: [daysAgo(21)], orbit: .weekly, now: now)
        XCTAssertLessThan(stale, fresh - 0.15,
            "Three quiet weeks on a weekly orbit should be visibly softer")
        XCTAssertGreaterThan(stale, LuminosityEngine.floorGlow, "…but nowhere near dark")
    }

    func testSameSilenceDimsDailyOrbitMoreThanRareOrbit() {
        let daily = LuminosityEngine.luminosity(momentDates: [daysAgo(30)], orbit: .mostDays, now: now)
        let rare  = LuminosityEngine.luminosity(momentDates: [daysAgo(30)], orbit: .rarely, now: now)
        XCTAssertLessThan(daily, rare)
    }

    // MARK: Contract: time only moves one way

    func testLuminosityIsMonotonicallyDecayingWithSilence() {
        var previous = Double.greatestFiniteMagnitude
        for days in stride(from: 0.0, through: 365.0, by: 5.0) {
            let l = LuminosityEngine.luminosity(momentDates: [daysAgo(days)], orbit: .weekly, now: now)
            XCTAssertLessThanOrEqual(l, previous)
            previous = l
        }
    }

    func testFutureDatedMomentsAreIgnored() {
        let l = LuminosityEngine.luminosity(
            momentDates: [now.addingTimeInterval(86_400)], orbit: .weekly, now: now)
        XCTAssertEqual(l, LuminosityEngine.floorGlow, accuracy: 0.001)
    }

    // MARK: States

    func testRememberedStarIsFixedAndNeverDims() {
        let l = LuminosityEngine.luminosity(
            momentDates: [daysAgo(2000)], orbit: .weekly, state: .remembered, now: now)
        XCTAssertEqual(l, LuminosityEngine.rememberedGlow, accuracy: 0.001)
    }

    // MARK: Rendering helpers

    func testTwinkleRateStaysInBounds() {
        for l in stride(from: 0.0, through: 1.0, by: 0.05) {
            let r = LuminosityEngine.twinkleRate(luminosity: l)
            XCTAssertGreaterThanOrEqual(r, 0.1)
            XCTAssertLessThanOrEqual(r, 0.6)
        }
    }

    func testSeededPositionsStayAwayFromEdges() {
        for i in 0..<200 {
            let p = SkyLayout.seededPosition(seed: i * 7919, index: i, total: 200)
            XCTAssertTrue((0.08...0.92).contains(p.x))
            XCTAssertTrue((0.10...0.88).contains(p.y))
        }
    }

    func testSeededPositionIsDeterministic() {
        let a = SkyLayout.seededPosition(seed: 42, index: 3, total: 10)
        let b = SkyLayout.seededPosition(seed: 42, index: 3, total: 10)
        XCTAssertEqual(a.x, b.x); XCTAssertEqual(a.y, b.y)
    }
}
