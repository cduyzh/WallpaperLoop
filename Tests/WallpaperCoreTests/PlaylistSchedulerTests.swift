import XCTest
@testable import WallpaperCore

final class PlaylistSchedulerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 24
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testSlotSelectionMidday() {
        let slots = [
            DynamicSlot(startMinute: 7 * 60, mediaID: UUID()),
            DynamicSlot(startMinute: 19 * 60, mediaID: UUID()),
        ]
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 12 * 60, slots: slots), slots[0])
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 19 * 60, slots: slots), slots[1])
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 23 * 60 + 59, slots: slots), slots[1])
    }

    func testSlotWrapAroundMidnight() {
        let dawn = DynamicSlot(startMinute: 6 * 60, mediaID: UUID())
        let night = DynamicSlot(startMinute: 20 * 60, mediaID: UUID())
        let slots = [dawn, night]
        // 00:30 属于昨晚 20:00 时段。
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 30, slots: slots), night)
        // 05:59 仍是夜间时段。
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 5 * 60 + 59, slots: slots), night)
        // 06:00 切到白天时段。
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 6 * 60, slots: slots), dawn)
    }

    func testUnsortedSlotsAreSortedInternally() {
        let late = DynamicSlot(startMinute: 22 * 60, mediaID: UUID())
        let early = DynamicSlot(startMinute: 8 * 60, mediaID: UUID())
        XCTAssertEqual(PlaylistScheduler.slot(forMinute: 10 * 60, slots: [late, early]), early)
    }

    func testActiveSlotUsesLocalTime() {
        let midnightSlot = DynamicSlot(startMinute: 0, mediaID: UUID())
        let slot = DynamicSlot(startMinute: 15 * 60, mediaID: UUID())
        // 10:00 生效的是 00:00 时段。
        let morning = PlaylistScheduler.activeSlot(at: date(hour: 10, minute: 0),
                                                   slots: [midnightSlot, slot], calendar: calendar)
        XCTAssertEqual(morning, midnightSlot)
        // 16:00 生效的是 15:00 时段。
        let afternoon = PlaylistScheduler.activeSlot(at: date(hour: 16, minute: 0),
                                                     slots: [midnightSlot, slot], calendar: calendar)
        XCTAssertEqual(afternoon, slot)
    }

    func testNextTransitionSameDay() {
        let slots = [
            DynamicSlot(startMinute: 7 * 60, mediaID: UUID()),
            DynamicSlot(startMinute: 19 * 60, mediaID: UUID()),
        ]
        let next = PlaylistScheduler.nextTransition(after: date(hour: 12, minute: 0), slots: slots, calendar: calendar)
        XCTAssertEqual(next, date(hour: 19, minute: 0))
    }

    func testNextTransitionWrapsToTomorrow() {
        let slots = [
            DynamicSlot(startMinute: 7 * 60, mediaID: UUID()),
            DynamicSlot(startMinute: 19 * 60, mediaID: UUID()),
        ]
        let next = PlaylistScheduler.nextTransition(after: date(hour: 20, minute: 0), slots: slots, calendar: calendar)
        XCTAssertEqual(next, calendar.date(byAdding: .day, value: 1, to: date(hour: 7, minute: 0)))
    }

    func testNextTransitionSingleSlotIsNil() {
        let slots = [DynamicSlot(startMinute: 0, mediaID: UUID())]
        XCTAssertNil(PlaylistScheduler.nextTransition(after: Date(), slots: slots, calendar: calendar))
    }

    func testNextIndexSequential() {
        XCTAssertEqual(PlaylistScheduler.nextIndex(after: nil, count: 3, shuffle: false, seed: 1), 0)
        XCTAssertEqual(PlaylistScheduler.nextIndex(after: 0, count: 3, shuffle: false, seed: 1), 1)
        XCTAssertEqual(PlaylistScheduler.nextIndex(after: 2, count: 3, shuffle: false, seed: 1), 0)
        XCTAssertNil(PlaylistScheduler.nextIndex(after: 0, count: 0, shuffle: false, seed: 1))
    }

    func testNextIndexShuffleAvoidsRepeat() {
        for index in 0..<10 {
            let next = PlaylistScheduler.nextIndex(after: index, count: 4, shuffle: true, seed: UInt64(index + 7))
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next, index)
        }
    }

    func testLocalMinuteOfDay() {
        XCTAssertEqual(PlaylistScheduler.localMinuteOfDay(date(hour: 0, minute: 0), calendar: calendar), 0)
        XCTAssertEqual(PlaylistScheduler.localMinuteOfDay(date(hour: 23, minute: 59), calendar: calendar), 23 * 60 + 59)
    }
}
