import SwiftUI

struct AdvancedSettingsPage: View {
    @ObservedObject var controller: MarsController
    @State private var confirmStandby = false
    private var validStandby: Bool {
        guard let value = controller.values[27] else { return false }
        return value.count == 1 && value[0] <= 1
    }
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "EXPERIMENTAL CONTROLS", title: "让声音适合此刻", subtitle: "依据原版控制逻辑重建，尚待你的 Mars 实物验证")
            Button("读取提示音与待机状态") { controller.readAdvancedSettings() }
                .buttonStyle(.bordered).disabled(!controller.connected || controller.busy)
                .accessibilityIdentifier("advanced.read")
            if controller.mcuVersion?.supportsAdvancedControls != true {
                Text(controller.mcuVersion == nil ? "尚未确认 MCU 版本，设置暂不可用。" : "此版本不满足原版高级控制条件，设置暂不可用。")
                    .font(.footnote).foregroundStyle(MarsTheme.muted)
            }
            VStack(spacing: 18) {
                Toggle("开关机提示音", isOn: Binding(
                    get: { controller.promptSounds?.power ?? false },
                    set: { controller.setPromptSound(power: $0) }))
                    .accessibilityIdentifier("advanced.powerSound")
                Toggle("起飞提示音", isOn: Binding(
                    get: { controller.promptSounds?.levitation ?? false },
                    set: { controller.setPromptSound(levitation: $0) }))
                    .accessibilityIdentifier("advanced.levitationSound")
                Text(controller.promptSounds == nil ? "等待设备返回有效提示音状态；开关位置不代表实际设置。" : "修改一个开关时，会保留另一个开关的当前设置。")
                    .font(.caption).foregroundStyle(MarsTheme.muted)
            }
            .padding(20).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            .disabled(!controller.canSetAdvancedControls || controller.promptSounds == nil)
            VStack(spacing: 16) {
                HStack {
                    Text("待机状态")
                    Spacer()
                    Text(validStandby ? (controller.value(27) == 1 ? "待机" : "开启") : "未确认")
                        .foregroundStyle(MarsTheme.muted)
                }
                Text("待机可能中断蓝牙。能否通过 App 唤醒取决于设备是否仍保持控制连接；必要时请按飞碟电源键。")
                    .font(.footnote).foregroundStyle(MarsTheme.muted)
                Button("进入待机") { confirmStandby = true }
                    .buttonStyle(.bordered).disabled(!controller.canSetAdvancedControls || !validStandby || controller.value(27) == 1)
                    .accessibilityIdentifier("advanced.standby")
                Button("唤醒设备") { controller.setStandby(false) }
                    .buttonStyle(.bordered).disabled(!controller.canSetAdvancedControls || !validStandby || controller.value(27) != 1)
            }.padding(20).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            ForEach([UInt8(8), 26, 27], id: \.self) { command in
                if let issue = controller.queryIssues[command] {
                    Text("\(commandLabel(command))：\(issue)").font(.caption).foregroundStyle(MarsTheme.muted)
                }
            }
            Text(controller.status).font(.footnote).foregroundStyle(MarsTheme.muted)
        }
        .confirmationDialog("让 Mars 进入待机？蓝牙可能随之断开。", isPresented: $confirmStandby, titleVisibility: .visible) {
            Button("进入待机") { controller.setStandby(true) }
            Button("取消", role: .cancel) {}
        }
    }
    private func commandLabel(_ command: UInt8) -> String {
        switch command { case 8: return "MCU"; case 26: return "提示音"; default: return "待机" }
    }
}

struct ConnectionListPage: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "CONNECTIONS · READ ONLY", title: "谁在连接 Mars", subtitle: "读取音箱记录的设备名称，不会断开其他设备")
            Button(controller.busy ? "正在读取…" : "读取连接列表") { controller.readConnectionLists() }
                .buttonStyle(.bordered).disabled(!controller.connected || controller.busy)
                .accessibilityIdentifier("connections.read")
            listSection("已连接", entries: controller.connectedEntries, countCommand: 18, entryCommand: 19)
            listSection("历史设备", entries: controller.historyEntries, countCommand: 20, entryCommand: 21)
            Text("实验性只读功能，尚待 Mars 实物验证。列表展示音箱返回的名称，不代表 iPhone 系统的蓝牙列表；不提供切换或移除设备操作。")
                .font(.footnote).foregroundStyle(MarsTheme.muted)
        }
    }
    private func listSection(_ title: String, entries: [UInt8: MarsConnectionEntry], countCommand: UInt8, entryCommand: UInt8) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let total = controller.value(countCommand) { Text("\(entries.count) / \(total)").font(.caption).foregroundStyle(MarsTheme.muted) }
            }
            ForEach(entries.values.sorted { $0.index < $1.index }) { entry in
                Label(entry.name, systemImage: "desktopcomputer.and.iphone").font(.subheadline)
            }
            if entries.isEmpty {
                Text(controller.value(countCommand) == 0 ? "音箱返回空列表" : "尚未读取到设备名称")
                    .font(.footnote).foregroundStyle(MarsTheme.muted)
            }
            if let issue = controller.queryIssues[countCommand] ?? controller.queryIssues[entryCommand] {
                Text(issue).font(.caption).foregroundStyle(MarsTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
    }
}

struct DeviceInformationPage: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "DEVICE INFORMATION", title: controller.displayName, subtitle: "只读版本信息，不涉及固件升级")
            VStack(spacing: 16) {
                LabeledContent("MCU", value: controller.mcuVersion?.label ?? "尚未读取")
                LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("控制连接", value: controller.connected ? "BLE 已连接" : "未连接")
            }.padding(20).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            Button("刷新设备状态") { controller.refresh() }
                .buttonStyle(.bordered).disabled(!controller.connected || controller.busy)
            if let issue = controller.queryIssues[8] { Text(issue).font(.caption).foregroundStyle(MarsTheme.muted) }
            Text("原版 3.0.11 对 Mars 使用 MCU 第二段大于 25 的高级功能条件。本 App 同时要求设备返回有效设置状态后才允许操作。满足版本条件并不等于已完成实物验证。")
                .font(.footnote).foregroundStyle(MarsTheme.muted)
        }
    }
}
