import SwiftUI
import CoreBluetooth

final class MarsController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var connected = false
    @Published var busy = false
    @Published var status = "连接 Mars 后读取实际状态"
    @Published var values: [UInt8: [UInt8]] = [:]
    @Published var lastConfirmed = "尚未读取"
    @Published private(set) var displayName = UserDefaults.standard.string(forKey: "marsDisplayName") ?? "Mars Speaker"
    @Published var feedback: MarsFeedback?
    @Published private(set) var pendingName = UserDefaults.standard.string(forKey: "marsPendingName")
    @Published private(set) var activeCommand: UInt8?
    var isConnecting: Bool { wantsConnection }
    private var central: CBCentralManager!
    private var device: CBPeripheral?
    private var channel: CBCharacteristic?
    @Published private var wantsConnection = false
    private var decoder = MarsFrameDecoder()
    private var sequence: UInt8 = 1
    private var queue: [Request] = []
    private var pending: Request?
    private var timer: Timer?
    private var connectTimer: Timer?
    private var seenResponses = Set<String>()
    private struct Request {
        let command: UInt8
        let payload: [UInt8]?
        let sequence: UInt8
        let expected: [UInt8]?
    }
    override init() { super.init() }
    func connect() {
        guard !connected, !wantsConnection else { return }
        wantsConnection = true
        status = "正在连接 Mars…"
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central.state == .poweredOn { find() }
    }
    private func find() {
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, !self.connected else { return }
            self.disconnect()
            self.status = "连接超时，请确认 Mars 已开启且在附近"
        }
        if let id = UserDefaults.standard.string(forKey: "marsPeripheralID"), let uuid = UUID(uuidString: id),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            attach(known)
        } else { central.scanForPeripherals(withServices: [CBUUID(string: "180F")]) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, wantsConnection { find() }
        else if central.state != .poweredOn {
            connected = false; channel = nil; queue.removeAll(); pending = nil; busy = false
            activeCommand = nil
            if [.poweredOff, .unauthorized, .unsupported].contains(central.state) { wantsConnection = false; device = nil }
            timer?.invalidate(); connectTimer?.invalidate()
            status = central.state == .unauthorized ? "请在系统设置允许本 App 使用蓝牙" : "等待蓝牙开启"
            }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let savedID = UserDefaults.standard.string(forKey: "marsPeripheralID")
        guard (peripheral.identifier.uuidString == savedID || name == displayName || name == "Mars by crazybaby"), device == nil else { return }
        central.stopScan(); attach(peripheral)
    }
    private func attach(_ peripheral: CBPeripheral) {
        device = peripheral; peripheral.delegate = self
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "marsPeripheralID")
        central.connect(peripheral)
    }
    func disconnect() {
        wantsConnection = false; connected = false; busy = false
        timer?.invalidate(); connectTimer?.invalidate()
        queue.removeAll(); pending = nil; channel = nil
        activeCommand = nil
        central?.stopScan()
        if let device { central?.cancelPeripheralConnection(device) }
        device = nil
        status = "已断开连接"
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        decoder = MarsFrameDecoder(); seenResponses.removeAll()
        peripheral.discoverServices([CBUUID(string: "180F")])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnect(); status = "连接失败：\(error?.localizedDescription ?? "未知原因")"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard device?.identifier == peripheral.identifier else { return }
        let unfinished = pending != nil
        disconnect()
        if unfinished { status = "连接已断开，最后操作结果未确认；未重发" }
        else if let error { status = "连接断开：\(error.localizedDescription)" }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: "180F") }) else {
            status = "未发现预期服务：\(error?.localizedDescription ?? "180F 不可见")"; return
        }
        peripheral.discoverCharacteristics([CBUUID(string: "2A19")], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "2A19") }),
              characteristic.properties.contains(.write), characteristic.properties.contains(.notify) else {
            status = "未发现已验证的读写通知通道"; return
        }
        channel = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else { status = "通知订阅失败"; return }
        connectTimer?.invalidate(); wantsConnection = false; connected = true
        status = "Mars 已连接，正在读取状态"
        refresh()
    }
    func refresh() {
        guard connected, !busy else { return }
        values.removeAll()
        for command: UInt8 in [3, 4, 13, 24, 25] { enqueue(command, payload: nil) }
        sendNext()
    }
    func set(_ command: UInt8, _ value: UInt8) {
        guard connected, !busy else { return }
        let range: ClosedRange<UInt8>?
        switch command { case 3: range = 0...4; case 4: range = 0...16; case 25: range = 0...15; case 13: range = 0...1; case 24: range = 0...3; default: range = nil }
        guard range?.contains(value) == true else { status = "参数超出已还原范围"; return }
        feedback = nil
        enqueue(command, payload: [value]); sendNext()
    }
    func rename(_ name: String) {
        guard connected, !busy else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 17 else {
            feedback = MarsFeedback(message: "名称请控制在 17 字节以内", style: .notice); return
        }
        feedback = nil
        pendingName = name
        UserDefaults.standard.set(name, forKey: "marsPendingName")
        enqueue(7, payload: MarsWire.escapedName(name)); sendNext()
    }
    func confirmPendingName() {
        guard let name = pendingName else { return }
        displayName = name
        UserDefaults.standard.set(name, forKey: "marsDisplayName")
        pendingName = nil
        UserDefaults.standard.removeObject(forKey: "marsPendingName")
        feedback = MarsFeedback(message: "设备名称已更新", style: .success)
    }
    private func nextSequence() -> UInt8 {
        let result = sequence; sequence = sequence == 127 ? 1 : sequence + 1; return result
    }
    private func enqueue(_ command: UInt8, payload: [UInt8]?, expected: [UInt8]? = nil, front: Bool = false) {
        let request = Request(command: command, payload: payload, sequence: nextSequence(), expected: expected)
        if front { queue.insert(request, at: 0) } else { queue.append(request) }
    }
    private func sendNext() {
        guard pending == nil, let device, let channel, connected else { return }
        guard !queue.isEmpty else {
            busy = false
            activeCommand = nil
            return
        }
        let request = queue.removeFirst()
        let packet = request.payload.map { MarsWire.set(request.command, value: $0, sequence: request.sequence) } ?? MarsWire.query(request.command, sequence: request.sequence)
        guard packet.count <= device.maximumWriteValueLength(for: .withResponse) else {
            status = "名称数据超过本次连接可写长度，未发送"; queue.removeAll(); busy = false; return
        }
        pending = request; busy = true; activeCommand = request.command
        status = request.payload == nil ? "正在查询状态…" : "已发送设置，等待音箱确认…"
        if request.command == 7, packet.count > 20 {
            // Mars' UART-like BLE path may not accept a complete long command
            // as one ATT value despite CoreBluetooth reporting a larger MTU.
            // These are consecutive parts of ONE frame, not retries.
            for offset in stride(from: 0, to: packet.count, by: 20) {
                let part = packet.subdata(in: offset..<min(offset + 20, packet.count))
                device.writeValue(part, for: channel, type: .withResponse)
            }
        } else { device.writeValue(packet, for: channel, type: .withResponse) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, let pending = self.pending else { return }
            self.pending = nil
            if pending.payload != nil || pending.expected != nil {
                self.queue.removeAll(); self.busy = false
                self.activeCommand = nil
                self.status = "设置结果未确认，请刷新状态；未自动重试"
                self.feedback = MarsFeedback(message: "暂未确认结果，请刷新设备状态", style: .notice)
            } else {
                self.status = "部分状态未返回"
                self.sendNext()
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // This Mars reports ATT invalid-length even when it processes the frame.
        // Never replay on this error; wait for checksum-validated protocol evidence.

    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, characteristic.uuid == channel?.uuid else { return }
        for frame in decoder.append(data) {
            if frame.kind == 0 {
                if let request = pending, frame.sequence == request.sequence, let payload = request.payload {
                    timer?.invalidate(); pending = nil
                    if request.command == 13 {
                        feedback = MarsFeedback(message: payload.first == 1 ? "升起指令已接收" : "降落指令已接收", style: .notice)
                    }
                    enqueue(request.command, payload: nil, expected: request.command == 7 ? MarsWire.unescape(payload) : payload, front: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + (request.command == 13 ? 2.0 : 0.1)) { [weak self] in self?.sendNext() }
                }
                continue
            }
            guard frame.body.count >= 2 else { continue }
            // Acknowledge valid incoming data frames, including repeated deliveries.
            if let device, let channel { device.writeValue(MarsWire.ack(frame.sequence), for: channel, type: .withResponse) }
            let fingerprint = "\(frame.sequence):\(frame.body)"
            let awaitingThisCommand = pending?.command == frame.command && pending?.payload == nil
            guard seenResponses.insert(fingerprint).inserted || awaitingThisCommand else { continue }
            if seenResponses.count > 128 { seenResponses.removeAll(); seenResponses.insert(fingerprint) }
            guard frame.operation == 2, let command = frame.command else { continue }
            values[command] = frame.payload
            lastConfirmed = Date().formatted(date: .omitted, time: .standard)
            if let request = pending, request.command == command, request.payload == nil {
                timer?.invalidate(); pending = nil
                let actual = command == 7 ? MarsWire.unescape(frame.payload) : frame.payload
                if let expected = request.expected {
                    let liftMatch = command == 13 && ((expected == [1] && [1,3,4].contains(Int(actual.first ?? 255))) || (expected == [0] && [0,2,5].contains(Int(actual.first ?? 255))))
                    let matched = actual == expected || liftMatch
                    if command == 7 {
                        if matched {
                            pendingName = String(bytes: expected, encoding: .utf8)
                            confirmPendingName()
                            status = "设备名称已确认"
                        } else {
                            status = "名称指令已接收，重启飞碟后核对"
                            feedback = MarsFeedback(message: "名称已发送，请重启飞碟后核对", style: .notice)
                        }
                    } else if command == 13, !matched {
                        status = "升降指令已接收，请观察飞碟动作"
                        feedback = MarsFeedback(message: "指令已接收，请观察飞碟动作", style: .notice)
                    } else {
                        status = matched ? "设置已由音箱状态返回确认" : "音箱返回与请求值不同，请检查当前状态"
                        feedback = MarsFeedback(message: matched ? "设置已更新" : "设备返回值与设置不同，请刷新核对", style: matched ? .success : .notice)
                    }
                } else { status = "已收到音箱实际状态" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.sendNext() }
            }
        }
    }
    func value(_ command: UInt8) -> Int? { values[command]?.first.map(Int.init) }
}
