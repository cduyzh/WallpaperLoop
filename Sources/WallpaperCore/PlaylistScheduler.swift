import Foundation

/// 播放列表与动态壁纸时段的纯逻辑调度。
public enum PlaylistScheduler {

    /// 顺序或随机取下一个条目下标；空列表返回 nil。
    public static func nextIndex(after index: Int?, count: Int, shuffle: Bool, seed: UInt64) -> Int? {
        guard count > 0 else { return nil }
        if shuffle {
            var generator = SeededRandom(seed: seed &+ UInt64(Date().timeIntervalSince1970))
            if count == 1 { return 0 }
            // 随机但避免与上一条相同。
            var candidate = Int(generator.next() % UInt64(count))
            if candidate == index { candidate = (candidate + 1) % count }
            return candidate
        }
        guard let current = index else { return 0 }
        return (current + 1) % count
    }

    /// 动态壁纸在指定本地时刻生效的时段。slots 必须升序且非空。
    public static func activeSlot(at date: Date, slots: [DynamicSlot], calendar: Calendar = .current) -> DynamicSlot? {
        guard !slots.isEmpty else { return nil }
        let minute = localMinuteOfDay(date, calendar: calendar)
        return slot(forMinute: minute, slots: slots)
    }

    /// 指定分钟（0–1439）生效的时段：取最后一个 startMinute <= minute 的时段；
    /// 若早于所有时段（深夜），回绕到最晚时段（昨日延续）。
    public static func slot(forMinute minute: Int, slots: [DynamicSlot]) -> DynamicSlot? {
        let sorted = slots.sorted { $0.startMinute < $1.startMinute }
        guard let earliest = sorted.first, let latest = sorted.last else { return nil }
        if minute >= latest.startMinute { return latest }
        if minute < earliest.startMinute { return latest }
        var active = earliest
        for slot in sorted where slot.startMinute <= minute {
            active = slot
        }
        return active
    }

    /// 下一次时段切换的本地时间；无切换（单时段）返回 nil。
    public static func nextTransition(after date: Date, slots: [DynamicSlot], calendar: Calendar = .current) -> Date? {
        let sorted = slots.sorted { $0.startMinute < $1.startMinute }
        guard sorted.count > 1 else { return nil }
        let minute = localMinuteOfDay(date, calendar: calendar)
        var nextMinute: Int? = sorted.first { $0.startMinute > minute }?.startMinute
        if nextMinute == nil { nextMinute = sorted[0].startMinute + 1440 }
        guard let target = nextMinute else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = target / 60
        components.minute = target % 60
        return calendar.date(from: components)
    }

    /// 本地时间的当日分钟数（0–1439）。
    public static func localMinuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return min(1439, max(0, hour * 60 + minute))
    }
}

/// 可注入种子的伪随机（xorshift64*），保证测试可复现。
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
