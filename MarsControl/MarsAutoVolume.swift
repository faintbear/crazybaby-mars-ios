import Foundation

/// Original Android 2.1.0 recurrence. The controller adds opt-in, limits and stop conditions.
enum MarsAutoVolumeSignalSource: String, CaseIterable, Identifiable {
    case iphoneBLE, speakerProtocol
    var id: String { rawValue }
    var title: String { self == .iphoneBLE ? "iPhone BLE" : "音箱原厂" }
}

struct MarsAutoVolumeAlgorithm {
    private var samples = 0
    private var average = 0
    private var previous = 0
    private(set) var latestTarget: Int?
    private(set) var adjustmentDue = false
    mutating func consume(rssi: Int) -> Int? {
        adjustmentDue = false
        let level = min(15, max(1, abs(rssi + 40) / 4))
        samples += 1
        average = (average + level) / 2
        guard samples > 2 else { return nil }
        samples = 0
        adjustmentDue = true
        average = min(15, average + 3)
        guard average != previous else { return nil }
        previous = average
        let result = average
        latestTarget = result
        average = level
        return result
    }
}

enum MarsProximitySignal {
    static func decode(_ payload: [UInt8]) -> Int? {
        // The original code reads the second payload byte as a signed Java byte.
        guard payload.count == 2 else { return nil }
        let rssi = Int(Int8(bitPattern: payload[1]))
        guard (-110 ... -10).contains(rssi) else { return nil }
        return rssi
    }
    static func rejectionMessage(_ payload: [UInt8]) -> String {
        guard payload.count == 2 else { return "信号响应长度 \(payload.count) 字节，与原版预期不同，已停止检测" }
        let value = Int(Int8(bitPattern: payload[1]))
        if value == 0 { return "音箱返回信号值 0，尚未取得可用信号；请确认音频连接与播放后重试" }
        return "音箱返回信号值 \(value)，超出当前验证范围，已停止自动音量"
    }
    static func originalLimitedTarget(_ suggestion: Int, current: Int, maximum: Int) -> Int? {
        guard (1...16).contains(current), (1...15).contains(maximum) else { return nil }
        return min(maximum, max(1, suggestion))
    }
}
