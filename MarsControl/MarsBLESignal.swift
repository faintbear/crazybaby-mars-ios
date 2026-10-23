import Foundation

enum MarsSignalPosition: String, CaseIterable, Identifiable {
    case unmarked, near, far, pocket
    var id: String { rawValue }
    var title: String {
        switch self { case .unmarked: return "未标记"; case .near: return "近处"; case .far: return "远处"; case .pocket: return "口袋" }
    }
}

struct MarsBLESignalTrace {
    struct Sample: Identifiable {
        let id: Int
        let elapsed: TimeInterval
        let raw: Int
        let median: Int
        let position: MarsSignalPosition
    }
    private(set) var samples: [Sample] = []
    var position = MarsSignalPosition.unmarked
    private var window: [Int] = []
    private var nextID = 0
    private var startedAt: Date?
    var latest: Sample? { samples.last }
    mutating func record(_ value: Int, at date: Date = Date()) -> Bool {
        // 127 is not a usable signal measurement. This view never drives volume.
        guard (-127...20).contains(value) else { return false }
        if startedAt == nil { startedAt = date }
        window.append(value)
        if window.count > 5 { window.removeFirst() }
        let ordered = window.sorted()
        let median = Self.middle(ordered)
        samples.append(Sample(id: nextID, elapsed: max(0, date.timeIntervalSince(startedAt!)), raw: value, median: median, position: position))
        nextID += 1
        if samples.count > 180 { samples.removeFirst(samples.count - 180) }
        return true
    }
    private static func middle(_ sorted: [Int]) -> Int {
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
    func summary(for position: MarsSignalPosition) -> (count: Int, median: Int, spread: Int)? {
        // Use the raw samples within each marked position; smoothing spans positions.
        let values = samples.filter { $0.position == position }.map(\.raw).sorted()
        guard !values.isEmpty else { return nil }
        return (values.count, Self.middle(values), values.last! - values.first!)
    }
}
