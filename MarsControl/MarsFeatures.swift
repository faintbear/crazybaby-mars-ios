import Foundation

/// Compatibility information inferred from the Android 3.0.11 control paths.
/// Firmware support must still be checked against a response from the speaker.
struct MarsMCUVersion: Equatable {
    let major: UInt8
    let revision: UInt8
    init?(_ payload: [UInt8]?) {
        guard let payload, payload.count == 2 else { return nil }
        major = payload[0]; revision = payload[1]
    }
    var label: String { "\(major).\(revision)" }
    var supportsAdvancedControls: Bool { revision > 25 }
}

struct MarsPromptSounds: Equatable {
    var levitation: Bool
    var power: Bool
    init?(_ payload: [UInt8]?) {
        guard let payload, payload.count == 1, payload[0] <= 3 else { return nil }
        levitation = payload[0] < 2
        power = payload[0] % 2 == 0
    }
    var encoded: UInt8 { (levitation ? 0 : 2) + (power ? 0 : 1) }
}

struct MarsConnectionEntry: Identifiable, Equatable {
    let index: UInt8
    let name: String
    var id: UInt8 { index }
    init?(_ payload: [UInt8]) {
        guard let index = payload.first, payload.count > 1,
              let name = String(bytes: payload.dropFirst(), encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters), !name.isEmpty else { return nil }
        self.index = index; self.name = name
    }
}

enum MarsEQ {
    static func name(_ value: Int) -> String {
        switch value {
        case 0: return "CrazyEQ"
        case 1: return "低音"
        case 2: return "室内"
        case 3: return "户外"
        case 4: return "旧版预设 4"
        default: return "未知预设 \(value)"
        }
    }
    static func subtitle(_ value: Int) -> String {
        switch value {
        case 0: return "CRAZYEQ"
        case 1: return "BASS"
        case 2: return "INDOORS"
        case 3: return "OUTDOORS"
        default: return "旧版兼容 · 不支持频段编辑"
        }
    }
}
