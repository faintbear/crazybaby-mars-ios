import SwiftUI

struct AutoVolumePage: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "PROXIMITY VOLUME", title: "让音量随距离变化", subtitle: "靠近降低，走远提高；上限由你设定，仅在前台运行")
            Picker("信号来源", selection: Binding(get: { controller.autoVolumeSignalSource }, set: { controller.selectAutoVolumeSignalSource($0) })) {
                ForEach(MarsAutoVolumeSignalSource.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text(controller.autoVolumeSignalSource == .iphoneBLE ? "默认采用已验证可读取的 iPhone BLE 信号，使用原版 2.1.0 公式与调节周期。" : "原厂信号查询在当前音箱上曾返回 0，保留此入口用于兼容其他固件。")
                .font(.footnote).foregroundStyle(MarsTheme.muted)
            VStack(spacing: 12) {
                Text((controller.proximityRSSI ?? controller.proximityReportedRSSI).map { "\($0)" } ?? "—")
                    .font(.system(size: 60, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text("\(controller.autoVolumeSignalSource.title) 信号强度 · dBm").font(.caption).foregroundStyle(MarsTheme.muted)
                Text("收到响应 \(controller.proximityResponseCount) 次 · 有效采样 \(controller.proximitySamples) 次").font(.caption).foregroundStyle(MarsTheme.muted)
                if controller.autoVolumeSignalSource == .speakerProtocol && controller.proximityReportedRSSI == 0 {
                    Text("0 暂不视为有效距离信号，不会据此调节音量")
                        .font(.caption).foregroundStyle(MarsTheme.muted)
                }
                if let suggestion = controller.proximitySuggestion {
                    Text("原算法建议 \(suggestion) 档 · 实际受音量上限约束")
                        .font(.caption).foregroundStyle(MarsTheme.muted)
                }
            }.frame(maxWidth: .infinity).padding(24)
                .background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            NavigationLink(value: MarsRoute.feature(.bleSignal)) {
                Label("测试 iPhone BLE 信号（只读）", systemImage: "waveform.path")
            }.buttonStyle(.bordered)
            Text(controller.proximityStatus).font(.footnote).foregroundStyle(MarsTheme.accent)
                .multilineTextAlignment(.center)
            Button(controller.autoVolumeMonitoring ? "停止检测与自动音量" : "开始检测") {
                if controller.autoVolumeMonitoring { controller.stopAutoVolume() }
                else { controller.startProximityMonitoring() }
            }.buttonStyle(.bordered)
                .disabled(!controller.autoVolumeMonitoring && (!controller.connected || controller.busy || controller.bleSignalAwaitingResponse || (controller.autoVolumeSignalSource == .iphoneBLE && controller.bleSignalRequiresReconnect)))
                .accessibilityIdentifier("proximity.monitor")
            VStack(spacing: 18) {
                Toggle("开启自动音量", isOn: Binding(
                    get: { controller.autoVolumeEnabled },
                    set: { enabled in
                        if enabled { controller.enableAutoVolume() }
                        else { controller.stopAutoVolume("已手动关闭；需要重新检测后才能再次开启") }
                    }))
                    .disabled(!controller.autoVolumeEnabled && !controller.canEnableAutoVolume)
                    .accessibilityIdentifier("proximity.enable")
                HStack {
                    Text("音量上限")
                    Spacer()
                    Text("\(controller.autoVolumeMaximum) / 15").monospacedDigit().foregroundStyle(MarsTheme.accent)
                }
                Slider(value: Binding(get: { Double(controller.autoVolumeMaximum) },
                                      set: { controller.setAutoVolumeMaximum(Int($0)) }), in: 1...15, step: 1)
                                        .accessibilityLabel("自动音量上限")
                Text("\(controller.value(4).map { "设备音量 \($0) / 16" } ?? "设备音量尚未读取")")
                    .font(.caption).foregroundStyle(MarsTheme.muted)
            }.padding(20).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            DisclosureGroup("信号检测详情") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(controller.proximityLastFrame).font(.caption.monospaced()).textSelection(.enabled)
                    Text("仅在本机保留最近 12 条信号响应，不包含设备名称或标识，不会自动上传。")
                        .font(.caption).foregroundStyle(MarsTheme.muted)
                    if FileManager.default.fileExists(atPath: controller.proximityReportURL.path) {
                        ShareLink("导出信号检测", item: controller.proximityReportURL)
                    }
                }.padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("点击开始检测，等待约 6 秒后打开自动音量。无需完成额外测试；信号有效且设备音量非静音时即可开启。")
                Text("按原版公式直接设置目标档位，可能跨越多档。音量上限由你设置并自动保存；首次默认为 8 / 15。自动音量不会取消静音。")
                Text("切换 App、锁屏、断线、读取其他设置或手动调音量都会停止，不会自动恢复。已发出的指令仍可能完成。手机留在原地时无法感知你的位置。")
                Text("iPhone BLE 与音箱原厂信号的测量侧不同；已验证信号采样及开启后音量降低；远近连续调节仍待验证，不保证响度恒定。")
            }.font(.footnote).foregroundStyle(MarsTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
