import SwiftUI

struct BLESignalTestPage: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "IPHONE BLE · READ ONLY", title: "观察距离与信号", subtitle: "测量来自 iPhone，与原厂 0x17 返回分开；不驱动自动音量")
            VStack(spacing: 12) {
                Text(controller.bleSignalTrace.latest.map { "\($0.raw)" } ?? "—")
                    .font(.system(size: 60, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text("当前信号 · dBm").font(.caption).foregroundStyle(MarsTheme.muted)
                Text(controller.bleSignalTrace.latest.map { "最近五点中位数 \($0.median) dBm" } ?? "等待采样")
                    .font(.subheadline).foregroundStyle(MarsTheme.accent)
                Text("保留最近 \(controller.bleSignalTrace.samples.count) 个采样").font(.caption).foregroundStyle(MarsTheme.muted)
                SignalTracePlot(samples: Array(controller.bleSignalTrace.samples.suffix(60)))
                    .frame(height: 110).accessibilityHidden(true)
                Text("曲线为平滑信号，范围 −110 至 0 dBm；不是距离刻度。")
                    .font(.caption2).foregroundStyle(MarsTheme.muted)
            }.padding(20).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            Text(controller.bleSignalStatus).font(.footnote).foregroundStyle(MarsTheme.accent).multilineTextAlignment(.center)
            Button(controller.bleSignalRunning ? "停止只读测试" : "开始新一轮只读测试") {
                if controller.bleSignalRunning { controller.stopBLESignalTest() }
                else { controller.startBLESignalTest() }
            }.buttonStyle(.bordered)
                .disabled(!controller.bleSignalRunning && (!controller.connected || controller.busy || controller.bleSignalAwaitingResponse || controller.bleSignalRequiresReconnect))
                .accessibilityIdentifier("bleSignal.startStop")
            Picker("当前位置标记", selection: Binding(get: { controller.bleSignalTrace.position }, set: { controller.markBLESignalPosition($0) })) {
                ForEach(MarsSignalPosition.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(!controller.bleSignalRunning)
            VStack(spacing: 14) {
                ForEach([MarsSignalPosition.near, .far, .pocket]) { position in
                    HStack {
                        Text(position.title)
                        Spacer()
                        if let summary = controller.bleSignalTrace.summary(for: position) {
                            Text("\(summary.count) 点 · 中位 \(summary.median) · 波动 \(summary.spread) dB")
                                .font(.caption).foregroundStyle(MarsTheme.muted)
                        } else { Text("未标记采样").font(.caption).foregroundStyle(MarsTheme.muted) }
                    }
                }
            }.padding(20).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            Text("依次标记并测试：近处静止约 10 秒 → 远处静止约 10 秒 → 原地将手机放入口袋约 10 秒。保持 App 前台。数字越接近 0，通常信号越强；人体和墙壁也会影响信号，不能直接换算成米。")
                .font(.footnote).foregroundStyle(MarsTheme.muted)
            Text("切换 App、锁屏或断线会停止；重新开始会清空当前一轮采样。记录仅留本机，最多 180 点，无设备名称或标识，不会自动上传。")
                .font(.footnote).foregroundStyle(MarsTheme.muted)
            if !controller.bleSignalTrace.samples.isEmpty {
                ShareLink("导出本轮信号记录", item: controller.bleSignalReportURL).font(.footnote)
            }
        }
    }
}

private struct SignalTracePlot: View {
    let samples: [MarsBLESignalTrace.Sample]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    for fraction in [0.0, 0.5, 1.0] {
                        let y = geometry.size.height * fraction
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }.stroke(MarsTheme.line, lineWidth: 1)
                Path { path in
                    for (index, sample) in samples.enumerated() {
                        let x = geometry.size.width * Double(index) / Double(max(samples.count - 1, 1))
                        let fraction = min(1, max(0, Double(sample.median + 110) / 110))
                        let point = CGPoint(x: x, y: geometry.size.height * (1 - fraction))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(MarsTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
