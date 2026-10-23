import SwiftUI
import CoreBluetooth

final class MarsController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var connected = false
    @Published var busy = false
    @Published var status = "连接 Mars 后读取实际状态"
    @Published var values: [UInt8: [UInt8]] = [:]
    @Published private(set) var connectedEntries: [UInt8: MarsConnectionEntry] = [:]
    @Published private(set) var historyEntries: [UInt8: MarsConnectionEntry] = [:]
    @Published private(set) var queryIssues: [UInt8: String] = [:]
    var mcuVersion: MarsMCUVersion? { MarsMCUVersion(values[8]) }
    var promptSounds: MarsPromptSounds? { MarsPromptSounds(values[26]) }
    var canSetAdvancedControls: Bool { connected && !busy && mcuVersion?.supportsAdvancedControls == true }
    @Published private(set) var autoVolumeMonitoring = false
    @Published private(set) var autoVolumeEnabled = false
    @Published private(set) var proximityRSSI: Int?
    @Published private(set) var proximityReportedRSSI: Int?
    @Published private(set) var proximityResponseCount = 0
    @Published private(set) var proximityRaw = "尚未读取"
    @Published private(set) var proximitySamples = 0
    @Published private(set) var proximitySuggestion: Int?
    @Published private(set) var proximityStatus = "先进行只读信号检测，不会改变音量"
    @Published private(set) var autoVolumeMaximum = 8
    @Published private(set) var proximityLastFrame = "尚未收到信号响应"
    private var proximityDiagnostics: [[String: Any]] = []
    var proximityReportURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mars-proximity.json")
    }
    private func recordProximityFrame(_ frame: MarsFrame) {
        let payload = MarsWire.unescape(frame.payload)
        proximityResponseCount += 1
        proximityReportedRSSI = payload.count == 2 ? Int(Int8(bitPattern: payload[1])) : nil
        proximityLastFrame = "长度 \(payload.count)：" + Data(payload).marsHex
        proximityDiagnostics.append(["time": ISO8601DateFormatter().string(from: Date()),
            "sequence": Int(frame.sequence), "body": Data(frame.body).marsHex,
            "payload": Data(payload).marsHex, "signedBytes": payload.map { Int(Int8(bitPattern: $0)) }])
        if proximityDiagnostics.count > 12 { proximityDiagnostics.removeFirst(proximityDiagnostics.count - 12) }
        let report: [String: Any] = ["version": 1, "command": 23, "frames": proximityDiagnostics]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: proximityReportURL, options: .atomic)
        }
    }
    private var autoVolumeTimer: Timer?
    private var proximityAlgorithm = MarsAutoVolumeAlgorithm()
    private var proximityAdjustmentDue = false
    private var lastProximitySample: Date?
    private var appActive = false
    var canEnableAutoVolume: Bool {
        appActive && connected && !busy && autoVolumeMonitoring && proximitySamples >= 3 &&
        (lastProximitySample.map { Date().timeIntervalSince($0) < 6 } ?? false) &&
        (value(4).map { (1...16).contains($0) } ?? false)
    }
    @Published private(set) var bleSignalRunning = false
    @Published private(set) var bleSignalAwaitingResponse = false
    @Published private(set) var bleSignalRequiresReconnect = false
    @Published private(set) var bleSignalTrace = MarsBLESignalTrace()
    @Published private(set) var bleSignalStatus = "仅测量 iPhone 侧 BLE 信号，不会调节音量"
    private var bleSignalTimer: Timer?
    private var bleSignalTimeout: Timer?
    var bleSignalReportURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mars-ble-signal.json")
    }
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
        let queryArguments: [UInt8]
        let automatic: Bool
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
            clearAdvancedState()
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
        clearAdvancedState()
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
        clearAdvancedState()
        for command: UInt8 in [3, 4, 13, 24, 25, 8] { enqueue(command, payload: nil) }
        sendNext()
    }
    func set(_ command: UInt8, _ value: UInt8) {
        if autoVolumeMonitoring { stopAutoVolume("手动操作设备，自动音量已停止") }
        guard connected, !busy else { return }
        let range: ClosedRange<UInt8>?
        switch command { case 3: range = 0...4; case 4: range = 0...16; case 25: range = 0...15; case 13: range = 0...1; case 24: range = 0...3; default: range = nil }
        guard range?.contains(value) == true else { status = "参数超出已还原范围"; return }
        feedback = nil
        enqueue(command, payload: [value]); sendNext()
    }
    func setAppActive(_ active: Bool) {
        appActive = active
        if !active {
            stopAutoVolume("已离开前台，自动音量与检测均已停止")
            stopBLESignalTest("已离开前台，BLE 只读测试停止")
        }
    }
    func startProximityMonitoring() {
        guard appActive, connected, !busy else { return }
        stopBLESignalTest("切换为原厂信号检测，BLE 测试停止")
        stopAutoVolume("开始只读信号检测")
        proximityRSSI = nil; proximitySamples = 0; proximitySuggestion = nil
        proximityRaw = "等待音箱返回"; lastProximitySample = nil
        proximityReportedRSSI = nil; proximityResponseCount = 0; proximityLastFrame = "等待音箱返回"
        proximityAlgorithm = MarsAutoVolumeAlgorithm()
        proximityAdjustmentDue = false
        autoVolumeMaximum = min(8, max(1, value(4) ?? 8))
        autoVolumeMonitoring = true
        proximityStatus = "只读检测中，请拿着 iPhone 走近、走远观察信号"
        autoVolumeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollProximity() }
        pollProximity()
    }
    func enableAutoVolume() {
        guard canEnableAutoVolume else { return }
        autoVolumeEnabled = true
        proximityAlgorithm = MarsAutoVolumeAlgorithm()
        proximityAdjustmentDue = false
        proximitySuggestion = nil
        proximityStatus = "自动音量已开启；前台运行，每次最多提高一档"
    }
    func setAutoVolumeMaximum(_ maximum: Int) {
        guard (1...15).contains(maximum) else { return }
        autoVolumeMaximum = maximum
    }
    func stopAutoVolume(_ reason: String = "已停止自动音量与信号检测") {
        autoVolumeTimer?.invalidate(); autoVolumeTimer = nil
        autoVolumeEnabled = false; autoVolumeMonitoring = false
        proximityAdjustmentDue = false
        lastProximitySample = nil
        queue.removeAll { $0.automatic && $0.expected == nil }
        if pending == nil && queue.isEmpty { busy = false; activeCommand = nil }
        proximityStatus = reason
    }
    private func pollProximity() {
        guard appActive, connected, autoVolumeMonitoring else { stopAutoVolume(); return }
        if let sample = lastProximitySample, Date().timeIntervalSince(sample) > 8 {
            stopAutoVolume("信号更新中断，已停止；不会自动恢复")
            return
        }
        guard !busy else { return }
        enqueue(23, payload: nil, automatic: true)
        enqueue(4, payload: nil, automatic: true)
        sendNext()
    }
    private func consumeProximity(_ payload: [UInt8]) {
        proximityRaw = Data(payload).marsHex
        guard let rssi = MarsProximitySignal.decode(payload) else {
            stopAutoVolume(MarsProximitySignal.rejectionMessage(payload))
            return
        }
        proximityRSSI = rssi; proximitySamples += 1; lastProximitySample = Date()
        _ = proximityAlgorithm.consume(rssi: rssi)
        proximitySuggestion = proximityAlgorithm.latestTarget
        proximityAdjustmentDue = proximityAlgorithm.adjustmentDue
    }
    private func applyAutomaticVolumeIfNeeded() {
        guard autoVolumeMonitoring, autoVolumeEnabled, appActive,
              let sample = lastProximitySample, Date().timeIntervalSince(sample) < 6,
              let current = value(4) else { return }
        guard current > 0 else { stopAutoVolume("音箱已静音，自动音量停止，不会自动取消静音"); return }
        guard proximityAdjustmentDue, let suggestion = proximitySuggestion else { return }
        proximityAdjustmentDue = false
        guard let target = MarsProximitySignal.boundedTarget(suggestion, current: current, maximum: autoVolumeMaximum), target != current else { return }
        enqueue(4, payload: [UInt8(target)], automatic: true)
    }
    func startBLESignalTest() {
        guard appActive, connected, !busy, !bleSignalAwaitingResponse, !bleSignalRequiresReconnect else { return }
        stopAutoVolume("已切换为 iPhone BLE 只读测试，自动音量保持关闭")
        bleSignalTrace = MarsBLESignalTrace()
        bleSignalRunning = true
        bleSignalStatus = "只读测试中，每秒采样；请标记位置并保持约 10 秒"
        saveBLESignalTrace()
        bleSignalTimer?.invalidate()
        bleSignalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pollBLESignal() }
        pollBLESignal()
    }
    func stopBLESignalTest(_ reason: String = "BLE 只读测试已停止，记录保留在本机") {
        bleSignalTimer?.invalidate(); bleSignalTimer = nil
        bleSignalRunning = false; bleSignalStatus = reason
        // Leave the single outstanding request tracked until its response or timeout.
    }
    func markBLESignalPosition(_ position: MarsSignalPosition) {
        bleSignalTrace.position = position
    }
    private func pollBLESignal() {
        guard appActive, connected, bleSignalRunning, let device else { return }
        guard !bleSignalAwaitingResponse else { return }
        bleSignalAwaitingResponse = true
        device.readRSSI()
        bleSignalTimeout?.invalidate()
        bleSignalTimeout = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self, self.bleSignalAwaitingResponse else { return }
            self.bleSignalAwaitingResponse = false
            self.bleSignalRequiresReconnect = true
            self.stopBLESignalTest("BLE 信号读取超时，请断开重连后再测；未自动重试")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral.identifier == device?.identifier, bleSignalAwaitingResponse else { return }
        bleSignalTimeout?.invalidate(); bleSignalAwaitingResponse = false
        guard bleSignalRunning, appActive, connected else { return }
        guard error == nil else {
            stopBLESignalTest("BLE 信号读取失败：" + (error?.localizedDescription ?? "未知错误"))
            return
        }
        guard bleSignalTrace.record(RSSI.intValue) else {
            stopBLESignalTest("iPhone 返回不可用的信号值，测试停止")
            return
        }
        saveBLESignalTrace()
    }
    private func saveBLESignalTrace() {
        let samples: [[String: Any]] = bleSignalTrace.samples.map {
            ["seconds": $0.elapsed, "raw": $0.raw, "median5": $0.median, "position": $0.position.rawValue]
        }
        let report: [String: Any] = ["version": 1, "source": "iphone-corebluetooth", "readOnly": true, "samples": samples]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: bleSignalReportURL, options: .atomic)
        }
    }
    private func clearAdvancedState() {
        stopBLESignalTest("设备连接已重置，BLE 只读测试停止")
        bleSignalTimeout?.invalidate(); bleSignalAwaitingResponse = false; bleSignalRequiresReconnect = false

        stopAutoVolume("设备状态已重置，请重新检测并手动开启自动音量")
        proximityRSSI = nil; proximitySamples = 0; proximitySuggestion = nil; proximityRaw = "尚未读取"
        proximityReportedRSSI = nil; proximityResponseCount = 0; proximityLastFrame = "尚未收到信号响应"

        for command: UInt8 in [8, 18, 19, 20, 21, 26, 27] { values.removeValue(forKey: command) }
        connectedEntries.removeAll(); historyEntries.removeAll(); queryIssues.removeAll()
    }
    func readAdvancedSettings() {
        if autoVolumeMonitoring { stopAutoVolume("操作其他设置，自动音量已停止") }
        guard connected, !busy else { return }
        for command: UInt8 in [8, 26, 27] {
            values.removeValue(forKey: command); queryIssues.removeValue(forKey: command)
            enqueue(command, payload: nil)
        }
        sendNext()
    }
    func readConnectionLists() {
        if autoVolumeMonitoring { stopAutoVolume("操作其他设置，自动音量已停止") }
        guard connected, !busy else { return }
        connectedEntries.removeAll(); historyEntries.removeAll()
        for command: UInt8 in [18, 19, 20, 21] {
            values.removeValue(forKey: command); queryIssues.removeValue(forKey: command)
        }
        enqueue(18, payload: nil); enqueue(20, payload: nil); sendNext()
    }
    func setPromptSound(levitation: Bool? = nil, power: Bool? = nil) {
        if autoVolumeMonitoring { stopAutoVolume("操作其他设置，自动音量已停止") }
        guard canSetAdvancedControls, var sounds = promptSounds else { return }
        if let levitation { sounds.levitation = levitation }
        if let power { sounds.power = power }
        guard sounds.encoded != values[26]?.first else { return }
        feedback = nil; enqueue(26, payload: [sounds.encoded]); sendNext()
    }
    func setStandby(_ enabled: Bool) {
        if autoVolumeMonitoring { stopAutoVolume("操作其他设置，自动音量已停止") }
        guard canSetAdvancedControls, let current = values[27], current.count == 1, current[0] <= 1 else { return }
        let target: UInt8 = enabled ? 1 : 0
        guard current != [target] else { return }
        feedback = nil; enqueue(27, payload: [target]); sendNext()
    }
    private func validResponse(_ command: UInt8, _ payload: [UInt8]) -> Bool {
        switch command {
        case 8: return MarsMCUVersion(payload) != nil
        case 23: return MarsProximitySignal.decode(payload) != nil
        case 26: return MarsPromptSounds(payload) != nil
        case 27: return payload.count == 1 && payload[0] <= 1
        case 18, 20: return payload.count == 1
        case 19, 21: return MarsConnectionEntry(payload) != nil
        default: return true
        }
    }
    func rename(_ name: String) {
        if autoVolumeMonitoring { stopAutoVolume("操作其他设置，自动音量已停止") }
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
    private func enqueue(_ command: UInt8, payload: [UInt8]?, expected: [UInt8]? = nil, front: Bool = false, queryArguments: [UInt8] = [], automatic: Bool = false) {
        let request = Request(command: command, payload: payload, sequence: nextSequence(), expected: expected, queryArguments: queryArguments, automatic: automatic)
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
        let packet = request.payload.map { MarsWire.set(request.command, value: $0, sequence: request.sequence) } ?? MarsWire.query(request.command, arguments: request.queryArguments, sequence: request.sequence)
        guard packet.count <= device.maximumWriteValueLength(for: .withResponse) else {
            status = "名称数据超过本次连接可写长度，未发送"; queue.removeAll(); busy = false; return
        }
        if request.command != 19 && request.command != 21 { queryIssues.removeValue(forKey: request.command) }
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
            if pending.automatic { self.stopAutoVolume("自动音量查询或设置超时，已停止；未重发") }
            self.queryIssues[pending.command] = "设备未返回有效状态"
            if pending.payload != nil || pending.expected != nil {
                if pending.command == 26 || pending.command == 27 { self.values.removeValue(forKey: pending.command) }
                self.queue.removeAll(); self.busy = false
                self.activeCommand = nil
                self.status = pending.command == 27 ? "待机可能使连接中断，结果未确认；未重发" : "设置结果未确认，请刷新状态；未自动重试"
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
                    enqueue(request.command, payload: nil, expected: request.command == 7 ? MarsWire.unescape(payload) : payload, front: true, automatic: request.automatic)
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
            let payload = [8, 18, 19, 20, 21, 23, 26, 27].contains(Int(command)) ? MarsWire.unescape(frame.payload) : frame.payload
            if command == 23 { recordProximityFrame(frame) }
            guard validResponse(command, payload) else {
                queryIssues[command] = "设备返回格式无法识别"
                if command == 23 {
                    proximityRaw = Data(payload).marsHex
                    // A rejected response is still a completed query, not a timeout.
                    if pending?.command == 23 && pending?.payload == nil {
                        timer?.invalidate(); pending = nil
                    }
                    let reason = MarsProximitySignal.rejectionMessage(payload)
                    stopAutoVolume(reason)
                    queryIssues[23] = reason
                    sendNext()
                }
                if command == 4 && pending?.automatic == true { stopAutoVolume("音量返回无效，已停止自动音量") }
                continue
            }
            if command == 19 || command == 21 {
                guard let request = pending, request.command == command, request.payload == nil,
                      payload.first == request.queryArguments.first else { continue }
            }
            if command == 4, pending?.automatic == true, (payload.count != 1 || payload[0] > 16) {
                stopAutoVolume("音量返回无效，已停止自动音量")
                continue
            }
            values[command] = payload
            if command != 19 && command != 21 { queryIssues.removeValue(forKey: command) }
            lastConfirmed = Date().formatted(date: .omitted, time: .standard)
            if let request = pending, request.command == command, request.payload == nil {
                timer?.invalidate(); pending = nil
                if request.automatic && request.expected == nil {
                    if command == 23 && autoVolumeMonitoring { consumeProximity(payload) }
                    if command == 4 { applyAutomaticVolumeIfNeeded() }
                }
                let actual = command == 7 ? MarsWire.unescape(frame.payload) : payload
                if let expected = request.expected {
                    let liftMatch = command == 13 && ((expected == [1] && [1,3,4].contains(Int(actual.first ?? 255))) || (expected == [0] && [0,2,5].contains(Int(actual.first ?? 255))))
                    let matched = actual == expected || liftMatch
                    if request.automatic && !matched { stopAutoVolume("音量回读与目标不同，自动音量已停止") }
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
                if command == 18 || command == 20, let count = payload.first {
                    let entryCommand: UInt8 = command == 18 ? 19 : 21
                    // A bounded list prevents a malformed count from flooding the speaker.
                    if count <= 16 {
                        for index in (0..<Int(count)).reversed() {
                            enqueue(entryCommand, payload: nil, front: true, queryArguments: [UInt8(index)])
                        }
                    } else { queryIssues[command] = "列表超过 16 项，未自动读取" }
                } else if let entry = MarsConnectionEntry(payload) {
                    if command == 19 { connectedEntries[entry.index] = entry }
                    if command == 21 { historyEntries[entry.index] = entry }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.sendNext() }
            }
        }
    }
    func value(_ command: UInt8) -> Int? { values[command]?.first.map(Int.init) }
}
