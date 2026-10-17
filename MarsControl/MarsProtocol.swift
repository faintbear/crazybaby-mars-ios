import Foundation

struct MarsFrame {
    let kind: UInt8
    let sequence: UInt8
    let body: [UInt8]
    var command: UInt8? { body.count >= 2 ? body[1] : nil }
    var operation: UInt8? { body.first }
    var payload: [UInt8] { body.count > 2 ? Array(body.dropFirst(2)) : [] }
}

enum MarsWire {
    static func frame(sequence: UInt8, body: [UInt8], kind: UInt8 = 1) -> Data {
        let length = UInt32(body.count)
        var bytes: [UInt8] = [0xE5, kind, sequence,
            UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)]
        bytes += body
        let checksum = bytes.dropFirst().reduce(UInt8(0)) { $0 &+ $1 }
        bytes += [checksum, 0xEA]
        return Data(bytes)
    }
    static func query(_ command: UInt8, sequence: UInt8) -> Data { frame(sequence: sequence, body: [1, command]) }
    static func set(_ command: UInt8, value: [UInt8], sequence: UInt8) -> Data { frame(sequence: sequence, body: [6, command] + value) }
    static func ack(_ sequence: UInt8) -> Data { frame(sequence: sequence, body: [], kind: 0) }
    static func escapedName(_ name: String) -> [UInt8] {
        name.utf8.flatMap { byte -> [UInt8] in
            switch byte { case 0xE5: return [0xEE, 0xF5]; case 0xEA: return [0xEE, 0xFA]; case 0xEE: return [0xEE, 0xFE]; default: return [byte] }
        }
    }
    static func unescape(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []; var i = 0
        while i < bytes.count {
            if bytes[i] == 0xEE, i + 1 < bytes.count, let byte = [0xF5: UInt8(0xE5), 0xFA: 0xEA, 0xFE: 0xEE][Int(bytes[i + 1])] {
                result.append(byte); i += 2
            } else { result.append(bytes[i]); i += 1 }
        }
        return result
    }
}

struct MarsFrameDecoder {
    private var bytes: [UInt8] = []
    mutating func append(_ data: Data) -> [MarsFrame] {
        bytes += data
        var frames: [MarsFrame] = []
        while !bytes.isEmpty {
            guard let start = bytes.firstIndex(of: 0xE5) else { bytes.removeAll(); break }
            if start > 0 { bytes.removeFirst(start) }
            guard bytes.count >= 7 else { break }
            let count = bytes[3...6].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard count <= 1024 else { bytes.removeFirst(); continue }
            let total = Int(count) + 9
            guard bytes.count >= total else { break }
            let checksum = bytes[1..<(total - 2)].reduce(UInt8(0)) { $0 &+ $1 }
            guard bytes[total - 1] == 0xEA, bytes[total - 2] == checksum, bytes[1] <= 1 else { bytes.removeFirst(); continue }
            frames.append(MarsFrame(kind: bytes[1], sequence: bytes[2], body: Array(bytes[7..<(total - 2)])))
            bytes.removeFirst(total)
        }
        return frames
    }
}

extension Data {
    var marsHex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
