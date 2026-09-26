import XCTest
@testable import SmartGroceryReminder

final class ReminderStatsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ kind: DiagnosticEntry.Kind, atMinute minute: Double) -> DiagnosticEntry {
        DiagnosticEntry(date: start.addingTimeInterval(minute * 60), kind: kind, message: "")
    }

    func testEmptyLog() {
        let stats = ReminderStats.compute(from: [])
        XCTAssertEqual(stats, ReminderStats())
        XCTAssertNil(stats.doneRate)
        XCTAssertNil(stats.medianMinutesToDone)
    }

    func testCountsEachKindAndIgnoresOthers() {
        let stats = ReminderStats.compute(from: [
            entry(.launch, atMinute: 0),
            entry(.unloadScheduled, atMinute: 1),
            entry(.snoozed, atMinute: 6),
            entry(.snoozed, atMinute: 16),
            entry(.storeReminderSent, atMinute: 30),
            entry(.regionEnter, atMinute: 31),
        ])
        XCTAssertEqual(stats.unloadScheduled, 1)
        XCTAssertEqual(stats.unloadDone, 0)
        XCTAssertEqual(stats.snoozed, 2)
        XCTAssertEqual(stats.storeRemindersSent, 1)
        XCTAssertEqual(stats.doneRate, 0)
    }

    func testDoneRateIsCappedAtOne() {
        let stats = ReminderStats.compute(from: [
            entry(.unloadDone, atMinute: 0),
            entry(.unloadScheduled, atMinute: 1),
            entry(.unloadDone, atMinute: 3),
        ])
        XCTAssertEqual(stats.doneRate, 1)
    }

    func testDoneWithoutScheduleIsCountedButNotTimed() {
        let stats = ReminderStats.compute(from: [entry(.unloadDone, atMinute: 5)])
        XCTAssertEqual(stats.unloadDone, 1)
        XCTAssertNil(stats.medianMinutesToDone)
        XCTAssertNil(stats.doneRate)
    }

    func testDonePairsWithLatestSchedule() {
        let stats = ReminderStats.compute(from: [
            entry(.unloadScheduled, atMinute: 0),
            entry(.unloadScheduled, atMinute: 10),
            entry(.unloadDone, atMinute: 14),
        ])
        XCTAssertEqual(stats.medianMinutesToDone, 4)
        XCTAssertEqual(stats.doneRate, 0.5)
    }

    func testMedianWithOddAndEvenCounts() {
        let odd = ReminderStats.compute(from: [
            entry(.unloadScheduled, atMinute: 0), entry(.unloadDone, atMinute: 2),
            entry(.unloadScheduled, atMinute: 10), entry(.unloadDone, atMinute: 20),
            entry(.unloadScheduled, atMinute: 30), entry(.unloadDone, atMinute: 36),
        ])
        XCTAssertEqual(odd.medianMinutesToDone, 6)

        let even = ReminderStats.compute(from: [
            entry(.unloadScheduled, atMinute: 0), entry(.unloadDone, atMinute: 2),
            entry(.unloadScheduled, atMinute: 10), entry(.unloadDone, atMinute: 16),
        ])
        XCTAssertEqual(even.medianMinutesToDone, 4)
    }

    func testEntriesOutOfOrderAreSortedByDate() {
        let stats = ReminderStats.compute(from: [
            entry(.unloadDone, atMinute: 8),
            entry(.unloadScheduled, atMinute: 3),
        ])
        XCTAssertEqual(stats.medianMinutesToDone, 5)
    }
}
