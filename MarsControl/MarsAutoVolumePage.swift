import SwiftUI

struct AutoVolumePage: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "PROXIMITY VOLUME · EXPERIMENTAL", title: "让音量随距离变化", subtitle: "基于原厂旧版算法重建，仅在 App 前台运行")
            VStack(spacing: 12) {
                Text((controller.proximityRSSI ?? controller.proximityReportedRSSI).map { "\($0)" } ?? "—")
                    .font(.system(size: 60, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text("音箱返回的信号强度 · dBm").font(.caption).foregroundStyle(MarsTheme.muted)
                Text("收到响应 \(controller.proximityResponseCount) 次 · 有效采样 \(controller.proximitySamples) 次").font(.caption).foregroundStyle(MarsTheme.muted)
                if controller.proximityReportedRSSI == 0 {
                    Text("0 暂不视为有效距离信号，不会据此调节音量")
                        .font(.caption).foregroundStyle(MarsTheme.muted)
                }
                if let suggestion = controller.proximitySuggestion {
                    Text("原算法建议 \(suggestion) 档 · 实际受上限与平滑限制")
                        .font(.caption).foregroundStyle(MarsTheme.muted)
                }
            }.frame(maxWidth: .infinity).padding(24)
                .background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            NavigationLink(value: MarsRoute.feature(.bleSignal)) {
                Label("测试 iPhone BLE 信号（只读）", systemImage: "waveform.path")
            }.buttonStyle(.bordered)
            Text(controller.proximityStatus).font(.footnote).foregroundStyle(MarsTheme.accent)
                .multilineTextAlignment(.center)
            Button(controller.autoVolumeMonitoring ? "停止检测与自动音量" : "开始只读信号检测") {
                if controller.autoVolumeMonitoring { controller.stopAutoVolume() }
                else { controller.startProximityMonitoring() }
            }.buttonStyle(.bordered)
                .disabled(!controller.autoVolumeMonitoring && (!controller.connected || controller.busy))
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
                    .disabled(!controller.autoVolumeMonitoring)
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
                Text("先拿着 iPhone 走近、走远，观察信号是否随之变化。至少取得三个有效采样后才能开启；这只验证返回格式，不代表距离测量已经准确。")
                Text("建议低音量播放测试。每次最多提高一档，降低上限可能触发更大的降幅。自动音量不会取消静音。")
                Text("切换 App、锁屏、断线、读取其他设置或手动调音量都会停止，不会自动恢复。已发出的指令仍可能完成。手机留在原地时无法感知你的位置。")
                Text("若音箱不返回有效信号，此功能保持不可用。当前尚未完成 Mars 实物验证，不保证听感响度恒定。")
            }.font(.footnote).foregroundStyle(MarsTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
