import SwiftUI

struct MarsFeedback: Identifiable {
    enum Style { case success, notice }
    let id = UUID()
    let message: String
    let style: Style
}

enum MarsTheme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.041)
    static let panel = Color(red: 0.075, green: 0.086, blue: 0.080)
    static let text = Color(red: 0.90, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.57, green: 0.62, blue: 0.59)
    static let accent = Color(red: 0.71, green: 0.84, blue: 0.77)
    static let line = Color.white.opacity(0.075)
}

enum MarsPage: String, CaseIterable, Identifiable {
    case levitation, pattern, brightness, eq, volume, name, autoVolume, bleSignal, settings, connections, information
    var id: String { rawValue }
    var title: String {
        switch self {
        case .levitation: return "悬浮控制"
        case .pattern: return "灯环模式"
        case .brightness: return "亮度"
        case .eq: return "均衡器"
        case .volume: return "音量"
        case .name: return "设备名称"
        case .autoVolume: return "自动音量"
        case .bleSignal: return "BLE 信号测试"
        case .settings: return "提示音与待机"
        case .connections: return "连接设备"
        case .information: return "设备信息"
        }
    }
    var symbol: String {
        switch self {
        case .levitation: return "arrow.up.and.down"
        case .pattern: return "circle.dotted"
        case .brightness: return "sun.max"
        case .eq: return "slider.vertical.3"
        case .volume: return "speaker.wave.2"
        case .name: return "pencil.line"
        case .autoVolume: return "dot.radiowaves.left.and.right"
        case .bleSignal: return "waveform.path"
        case .settings: return "switch.2"
        case .connections: return "iphone.and.arrow.forward"
        case .information: return "info.circle"
        }
    }
}

enum MarsRoute: Hashable {
    case device
    case feature(MarsPage)
}

struct MarsInterface: View {
    @ObservedObject var controller: MarsController
    @State private var showHelp = false
    @State private var path: [MarsRoute] = []
    var body: some View {
        NavigationStack(path: $path) {
            DeviceListPage(controller: controller)
                .navigationDestination(for: MarsRoute.self) { route in
                    switch route {
                    case .device: MarsDevicePage(controller: controller)
                    case .feature(let page): MarsDetailPage(page: page, controller: controller)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("播放与连接帮助", systemImage: "questionmark.circle") { showHelp = true }
                            if controller.connected || controller.isConnecting {
                                Divider()
                                Button("断开连接", systemImage: "xmark.circle") { controller.disconnect() }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal").font(.system(size: 19)).frame(width: 40, height: 44)
                        }
                        .accessibilityLabel("菜单")
                        .accessibilityIdentifier("mars.menu")
                    }
                }
        }
        .tint(MarsTheme.accent)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let feedback = controller.feedback {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feedback.style == .success ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(MarsTheme.accent)
                    Text(feedback.message).font(.subheadline).foregroundStyle(MarsTheme.text).frame(maxWidth: .infinity, alignment: .leading)
                    Button { controller.feedback = nil } label: { Image(systemName: "xmark").font(.caption).frame(width: 28, height: 28) }
                        .accessibilityLabel("关闭提示")
                }
                .padding(16)
                .background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MarsTheme.line))
                .padding(.horizontal, 20).padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: feedback.id) {
                    try? await Task.sleep(for: .seconds(6))
                    if !Task.isCancelled, controller.feedback?.id == feedback.id { controller.feedback = nil }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.feedback?.id)
        .sheet(isPresented: $showHelp) { ConnectionHelpPage() }

    }
}

struct DeviceListPage: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("我的设备").font(.caption).tracking(2)
                    Rectangle().fill(MarsTheme.line).frame(height: 1)
                    Text("01").font(.caption.monospacedDigit())
                }
                .foregroundStyle(MarsTheme.muted).padding(.top, 35).padding(.bottom, 20)

                NavigationLink(value: MarsRoute.device) {
                    HStack(spacing: 15) {
                        MarsDiscIcon().frame(width: 48, height: 40)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(controller.displayName).font(.system(size: 16, weight: .medium)).foregroundStyle(MarsTheme.text).multilineTextAlignment(.leading)
                            ConnectionLabel(controller: controller)
                        }
                        Spacer(minLength: 5)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(MarsTheme.muted)
                    }
                    .padding(.vertical, 22).padding(.horizontal, 17)
                    .background(MarsTheme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(MarsTheme.line))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mars.device")

                VStack(spacing: 2) {
                    MarsSpeakerArt(lifted: true, lightLevel: 0.65).frame(height: 300)
                        .accessibilityHidden(true)
                    Text("MARS").font(.system(size: 24, weight: .light, design: .rounded)).tracking(9).foregroundStyle(MarsTheme.text.opacity(0.8))
                    Text("by crazybaby").font(.system(size: 11)).tracking(3).foregroundStyle(MarsTheme.muted).padding(.top, 9)
                }
                .frame(maxWidth: .infinity).padding(.top, 35)

                VStack(spacing: 12) {
                    Text(controller.connected ? "选择设备，开始控制" : "开启音箱，轻触设备以连接")
                        .font(.footnote).foregroundStyle(MarsTheme.muted)
                    if !controller.connected {
                        Text("音乐播放请在 iPhone 蓝牙设置中连接 Mars")
                            .font(.caption).foregroundStyle(MarsTheme.muted.opacity(0.8)).multilineTextAlignment(.center)
                    }
                }.frame(maxWidth: .infinity).padding(.top, 34).padding(.bottom, 35)
            }
            .padding(.horizontal, 24)
        }
        .marsBackground()
        .navigationTitle("设备")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MarsDevicePage: View {
    @ObservedObject var controller: MarsController
    @State private var didRequestConnection = false
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    ConnectionLabel(controller: controller)
                    Spacer()
                    if controller.connected {
                        Button { controller.refresh() } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 15)).frame(width: 40, height: 40)
                        }.disabled(controller.busy).accessibilityLabel("刷新设备状态")
                    } else {
                        Button(controller.isConnecting ? "取消" : "连接") {
                            if controller.isConnecting { controller.disconnect() } else { controller.connect() }
                        }.font(.subheadline)
                    }
                }.padding(.horizontal, 25).padding(.top, 8)

                MarsSpeakerArt(lifted: controller.value(13).map { [1,3,4].contains($0) } ?? true, lightLevel: Double(controller.value(25) ?? 10) / 15)
                    .frame(height: 230).accessibilityHidden(true)
                HStack(spacing: 10) {
                    Text("设备控制").font(.caption).tracking(1.5)
                    Rectangle().fill(MarsTheme.line).frame(height: 1)
                    Text(String(format: "%02d", MarsPage.allCases.count)).font(.caption.monospacedDigit())
                }.foregroundStyle(MarsTheme.muted).padding(.horizontal, 25).padding(.bottom, 13)

                VStack(spacing: 0) {
                    ForEach(MarsPage.allCases) { page in
                        NavigationLink(value: MarsRoute.feature(page)) {
                            HStack(spacing: 16) {
                                Image(systemName: page.symbol).font(.system(size: 18, weight: .light)).foregroundStyle(MarsTheme.muted).frame(width: 25)
                                Text(page.title).font(.system(size: 16)).foregroundStyle(MarsTheme.text)
                                Spacer(minLength: 8)
                                Text(summary(page)).font(.caption).foregroundStyle(MarsTheme.muted).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(MarsTheme.muted.opacity(0.7))
                            }
                            .padding(.horizontal, 25).padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("feature.\(page.rawValue)")
                        if page != MarsPage.allCases.last { Rectangle().fill(MarsTheme.line).frame(height: 0.5).padding(.leading, 66) }
                    }
                }
                .background(MarsTheme.panel.opacity(0.38))
                if controller.busy {
                    HStack(spacing: 9) { ProgressView().controlSize(.mini); Text("正在同步设备状态").font(.caption) }
                        .foregroundStyle(MarsTheme.muted).padding(.top, 24)
                } else if controller.lastConfirmed != "尚未读取" {
                    Text("上次同步  \(controller.lastConfirmed)").font(.caption2).foregroundStyle(MarsTheme.muted).padding(.top, 25)
                }
                if !controller.connected && !controller.isConnecting {
                    Text(controller.status).font(.footnote).foregroundStyle(MarsTheme.muted).multilineTextAlignment(.center).padding(24)
                }
            }.padding(.bottom, 30)
        }
        .marsBackground()
        .navigationTitle(controller.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didRequestConnection {
                didRequestConnection = true
                if !controller.connected { controller.connect() }
            }
        }
    }
    private func summary(_ page: MarsPage) -> String {
        guard controller.connected else { return "" }
        switch page {
        case .levitation: return liftDescription(controller.value(13))
        case .pattern: return controller.value(24).map { "模式 \($0 + 1)" } ?? "—"
        case .brightness: return controller.value(25).map { "\(Int(Double($0) / 15 * 100))%" } ?? "—"
        case .eq: return controller.value(3).map(MarsEQ.name) ?? "—"
        case .volume: return controller.value(4).map { $0 == 0 ? "静音" : "\($0) / 16" } ?? "—"
        case .name: return ""
        case .autoVolume: return controller.autoVolumeEnabled ? "运行中" : "实验功能"
        case .bleSignal: return controller.bleSignalRunning ? "只读采样中" : "只读"
        case .settings: return "实验功能"
        case .connections: return "只读"
        case .information: return controller.mcuVersion?.label ?? "—"
        }
    }
}

struct MarsDetailPage: View {
    let page: MarsPage
    @ObservedObject var controller: MarsController
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !controller.connected { DisconnectedBanner(controller: controller).padding(.bottom, 24) }
                switch page {
                case .levitation: LevitationPage(controller: controller)
                case .pattern: PatternPage(controller: controller)
                case .brightness: LevelPage(controller: controller, command: 25)
                case .volume: LevelPage(controller: controller, command: 4)
                case .eq: EQPage(controller: controller)
                case .name: NamePage(controller: controller)
                case .autoVolume: AutoVolumePage(controller: controller)
                case .bleSignal: BLESignalTestPage(controller: controller)
                case .settings: AdvancedSettingsPage(controller: controller)
                case .connections: ConnectionListPage(controller: controller)
                case .information: DeviceInformationPage(controller: controller)
                }
            }.padding(.horizontal, 25).padding(.top, 28).padding(.bottom, 35)
        }
        .marsBackground()
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LevitationPage: View {
    @ObservedObject var controller: MarsController
    @GestureState private var drag: CGFloat = 0
    private var enabled: Bool { controller.connected && !controller.busy }
    var body: some View {
        VStack(spacing: 22) {
            PageHeading(eyebrow: "LEVITATION", title: "让音乐，轻轻升起", subtitle: "向上轻扫升起，向下轻扫降落")
            MarsSpeakerArt(lifted: controller.value(13).map { [1,3,4].contains($0) } ?? true, lightLevel: Double(controller.value(25) ?? 10) / 15)
                .frame(height: 300).offset(y: min(30, max(-30, drag * 0.2)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 25).updating($drag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        guard enabled else { return }
                        if value.translation.height < -50 { controller.set(13, 1) }
                        else if value.translation.height > 50 { controller.set(13, 0) }
                    })
                .accessibilityLabel("悬浮音箱")
                .accessibilityAction(named: "升起") { if enabled { controller.set(13, 1) } }
                .accessibilityAction(named: "降落") { if enabled { controller.set(13, 0) } }
            Text(liftDescription(controller.value(13))).font(.subheadline).foregroundStyle(MarsTheme.accent)
            HStack(spacing: 14) {
                ActionButton(title: "升起", symbol: "arrow.up", prominent: true) { controller.set(13, 1) }
                ActionButton(title: "降落", symbol: "arrow.down", prominent: false) { controller.set(13, 0) }
            }.disabled(!enabled)
            Text("请先将飞碟放好，并保持底座电源开启。")
                .font(.footnote).foregroundStyle(MarsTheme.muted).multilineTextAlignment(.center).padding(.top, 7)
            WorkingLabel(controller: controller, command: 13)
        }
    }
}

struct LevelPage: View {
    @ObservedObject var controller: MarsController
    let command: UInt8
    @State private var draft = 0.0
    @State private var editing = false
    private var maximum: Double { command == 25 ? 15 : 16 }
    private var enabled: Bool { controller.connected && !controller.busy && controller.value(command) != nil }
    private var isBrightness: Bool { command == 25 }
    var body: some View {
        VStack(spacing: 30) {
            PageHeading(eyebrow: isBrightness ? "BRIGHTNESS" : "VOLUME", title: isBrightness ? "恰到好处的光" : "找到舒适的音量", subtitle: "拖动滑杆，松手后应用")
            ZStack {
                Circle().stroke(MarsTheme.line, lineWidth: 1).frame(width: 225, height: 225)
                Circle().trim(from: 0, to: draft / maximum).stroke(MarsTheme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 225, height: 225).rotationEffect(.degrees(-90))
                VStack(spacing: 16) {
                    Image(systemName: isBrightness ? "sun.max" : (draft == 0 ? "speaker.slash" : "speaker.wave.2"))
                        .font(.system(size: 30, weight: .ultraLight)).foregroundStyle(MarsTheme.accent)
                    Text(controller.value(command) == nil ? "—" : "\(Int((draft / maximum * 100).rounded()))")
                        .font(.system(size: 65, weight: .ultraLight, design: .rounded)).monospacedDigit().foregroundStyle(MarsTheme.text)
                    Text("PERCENT").font(.system(size: 9)).tracking(3).foregroundStyle(MarsTheme.muted)
                }
            }.padding(.vertical, 25).accessibilityElement(children: .ignore)
                .accessibilityLabel(isBrightness ? "亮度" : "音量")
                .accessibilityValue(controller.value(command) == nil ? "未读取" : "百分之\(Int(draft / maximum * 100))")
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    Image(systemName: isBrightness ? "sun.min" : "speaker").foregroundStyle(MarsTheme.muted)
                    Slider(value: $draft, in: 0...maximum, step: 1, onEditingChanged: { changed in
                        if changed && command == 4 && controller.autoVolumeMonitoring {
                            controller.stopAutoVolume("手动调节音量，自动音量已停止")
                        }
                        editing = changed
                        if !changed, enabled, Int(draft) != controller.value(command) { controller.set(command, UInt8(draft)) }
                    })
                    .tint(MarsTheme.accent).disabled(!enabled)
                    .accessibilityLabel(isBrightness ? "调节亮度" : "调节音量")
                    Image(systemName: isBrightness ? "sun.max" : "speaker.wave.3").foregroundStyle(MarsTheme.muted)
                }
                HStack {
                    Text(isBrightness ? "最低" : "静音")
                    Spacer()
                    Text("最高")
                }.font(.caption).foregroundStyle(MarsTheme.muted)
                if let actual = controller.value(command) {
                    Text("\(controller.connected ? "设备当前" : "上次读取")  \(Int((Double(actual) / maximum * 100).rounded()))%")
                        .font(.caption).foregroundStyle(MarsTheme.muted).padding(.top, 10)
                }
            }
            WorkingLabel(controller: controller, command: command)
            if !isBrightness {
                Text("听音乐前，请在播放界面将音频输出选为 Mars。")
                    .font(.footnote).foregroundStyle(MarsTheme.muted).multilineTextAlignment(.center)
            }
        }
        .onAppear { sync() }
        .onChange(of: controller.value(command)) { _, _ in if !editing { sync() } }
    }
    private func sync() {
        if let value = controller.value(command) { draft = min(maximum, max(0, Double(value))) }
    }
}

struct PatternPage: View {
    @ObservedObject var controller: MarsController
    private var enabled: Bool { controller.connected && !controller.busy }
    var body: some View {
        VStack(spacing: 28) {
            PageHeading(eyebrow: "LIGHT BELT", title: "换一种光的节奏", subtitle: "轻触模式，切换飞碟灯环")
            RingMotif().frame(height: 190).accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(0..<4) { index in
                    SelectionRow(title: "模式 \(index + 1)", subtitle: "LIGHT PATTERN 0\(index + 1)", selected: controller.value(24) == index) {
                        controller.set(24, UInt8(index))
                    }.disabled(!enabled || controller.value(24) == index)
                    if index < 3 { Rectangle().fill(MarsTheme.line).frame(height: 0.5).padding(.leading, 20) }
                }
            }.background(MarsTheme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 17))
            WorkingLabel(controller: controller, command: 24)
        }
    }
}

struct EQPage: View {
    @ObservedObject var controller: MarsController
    private var enabled: Bool { controller.connected && !controller.busy }
    var body: some View {
        VStack(spacing: 24) {
            PageHeading(eyebrow: "EQUALIZER", title: "听见不同的层次", subtitle: "播放一首熟悉的歌，再切换预设对比")
            HStack(alignment: .center, spacing: 10) {
                ForEach(0..<13) { index in
                    Capsule().fill(MarsTheme.accent.opacity(index % 3 == 0 ? 0.8 : 0.25))
                        .frame(width: 4, height: [22.0,40,68,94,63,112,138,112,63,94,68,40,22][index])
                }
            }.frame(height: 175).accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(0..<5) { index in
                    SelectionRow(title: MarsEQ.name(index), subtitle: MarsEQ.subtitle(index), selected: controller.value(3) == index) {
                        controller.set(3, UInt8(index))
                    }.disabled(!enabled || controller.value(3) == index)
                    if index < 4 { Rectangle().fill(MarsTheme.line).frame(height: 0.5).padding(.leading, 20) }
                }
            }.background(MarsTheme.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 17))
            WorkingLabel(controller: controller, command: 3)
        }
    }
}

struct NamePage: View {
    @ObservedObject var controller: MarsController
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var count: Int { trimmed.utf8.count }
    private var canSave: Bool { controller.connected && !controller.busy && count > 0 && count <= 17 && trimmed != controller.displayName }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(eyebrow: "DEVICE NAME", title: "给 Mars 一个名字", subtitle: "名称会显示在设备列表中")
            MarsDiscIcon().frame(width: 90, height: 65).frame(maxWidth: .infinity).padding(.vertical, 25).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 15) {
                Text("设备名称").font(.caption).foregroundStyle(MarsTheme.muted)
                HStack(spacing: 12) {
                    TextField("输入名称", text: $draft)
                        .font(.system(size: 18)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).submitLabel(.done).onSubmit { focused = false }
                        .accessibilityIdentifier("mars.name.input")
                    if !draft.isEmpty { Button { draft = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MarsTheme.muted) }.accessibilityLabel("清空名称") }
                }.padding(18).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text(count > 17 ? "名称过长，请缩短一些" : "最多 17 字节，中文通常占 3 字节")
                    Spacer()
                    Text("\(count)/17").monospacedDigit()
                }.font(.caption).foregroundStyle(count > 17 ? Color.orange.opacity(0.9) : MarsTheme.muted)
            }
            ActionButton(title: "保存名称", symbol: "checkmark", prominent: true) {
                focused = false; controller.rename(trimmed)
            }.disabled(!canSave)
            WorkingLabel(controller: controller, command: 7).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Label("保存后，需要重启飞碟", systemImage: "arrow.clockwise")
                    .font(.subheadline).foregroundStyle(MarsTheme.text)
                Text("先让飞碟降落，再关机重开。在 iPhone 蓝牙设置中核对新名称后，可在下方确认。")
                    .font(.footnote).foregroundStyle(MarsTheme.muted).lineSpacing(4)
            }.padding(.top, 5)
            if let pending = controller.pendingName {
                VStack(alignment: .leading, spacing: 14) {
                    Text("待确认名称").font(.caption).foregroundStyle(MarsTheme.muted)
                    Text(pending).font(.subheadline).foregroundStyle(MarsTheme.text)
                    Button("已重启，名称已更新") { controller.confirmPendingName() }.font(.subheadline).tint(MarsTheme.accent)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear { draft = controller.pendingName ?? controller.displayName }
    }
}

struct ActionButton: View {
    let title: String
    let symbol: String
    let prominent: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 15, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                .foregroundStyle(prominent ? MarsTheme.background : MarsTheme.text)
                .background(prominent ? MarsTheme.accent : MarsTheme.panel, in: RoundedRectangle(cornerRadius: 13))
                .opacity(enabled ? 1 : 0.65)
        }.buttonStyle(.plain)
    }
}

struct SelectionRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle().stroke(selected ? MarsTheme.accent : MarsTheme.muted.opacity(0.45), lineWidth: 1).frame(width: 21, height: 21)
                    .overlay { if selected { Circle().fill(MarsTheme.accent).frame(width: 7, height: 7) } }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16)).foregroundStyle(MarsTheme.text)
                    Text(subtitle).font(.system(size: 9)).tracking(1.3).foregroundStyle(MarsTheme.muted)
                }
                Spacer()
                if selected { Text("当前").font(.caption).foregroundStyle(MarsTheme.accent) }
            }.padding(.horizontal, 20).padding(.vertical, 17).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WorkingLabel: View {
    @ObservedObject var controller: MarsController
    let command: UInt8
    var body: some View {
        if controller.busy && controller.activeCommand == command {
            HStack(spacing: 9) { ProgressView().controlSize(.mini); Text("正在确认设备设置").font(.caption) }
                .foregroundStyle(MarsTheme.muted).padding(.vertical, 6)
        }
    }
}

struct ConnectionLabel: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        HStack(spacing: 7) {
            if controller.isConnecting { ProgressView().controlSize(.mini) }
            else { Circle().fill(controller.connected ? MarsTheme.accent : MarsTheme.muted.opacity(0.7)).frame(width: 5, height: 5) }
            Text(controller.isConnecting ? "正在连接" : controller.connected ? "已连接" : "未连接")
                .font(.caption).foregroundStyle(controller.connected ? MarsTheme.accent : MarsTheme.muted)
        }
    }
}

struct DisconnectedBanner: View {
    @ObservedObject var controller: MarsController
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(MarsTheme.muted)
            Text(controller.isConnecting ? "正在连接设备…" : "连接 Mars 后即可调节")
                .font(.footnote).foregroundStyle(MarsTheme.muted)
            Spacer()
            if !controller.isConnecting { Button("连接") { controller.connect() }.font(.footnote) }
        }.padding(15).background(MarsTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 13) {
            Text(eyebrow).font(.system(size: 9, weight: .medium)).tracking(3).foregroundStyle(MarsTheme.accent.opacity(0.8))
            Text(title).font(.system(size: 24, weight: .light)).foregroundStyle(MarsTheme.text).multilineTextAlignment(.center)
            Text(subtitle).font(.footnote).foregroundStyle(MarsTheme.muted).multilineTextAlignment(.center).lineSpacing(3)
        }.frame(maxWidth: .infinity)
    }
}

struct MarsDiscIcon: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.black).frame(height: 12).offset(y: 10).blur(radius: 5)
            Ellipse().fill(LinearGradient(colors: [Color(white: 0.27), .black], startPoint: .top, endPoint: .bottom)).frame(height: 20)
                .overlay(Ellipse().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
            Ellipse().stroke(MarsTheme.accent.opacity(0.65), lineWidth: 0.8).frame(height: 12).offset(y: 4)
        }
    }
}

struct MarsSpeakerArt: View {
    var lifted: Bool
    var lightLevel: Double
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 320, geometry.size.height / 300)
            ZStack {
                Ellipse().fill(MarsTheme.accent.opacity(0.035)).frame(width: 260, height: 160).blur(radius: 30).offset(y: 10)
                Ellipse().fill(.black.opacity(0.7)).frame(width: 170, height: 25).blur(radius: 10).offset(y: 132)
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.055), Color(white: 0.13)], startPoint: .leading, endPoint: .trailing))
                    RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.7)
                    VStack {
                        Ellipse().fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)).frame(height: 25)
                            .overlay(Ellipse().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                        Spacer()
                        Text("crazybaby").font(.system(size: 7, weight: .light)).tracking(0.7).foregroundStyle(.white.opacity(0.22)).padding(.bottom, 28)
                        Capsule().fill(MarsTheme.accent.opacity(0.35)).frame(width: 12, height: 1).padding(.bottom, 12)
                    }
                }.frame(width: 108, height: 147).offset(y: 55)
                ZStack {
                    Ellipse().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.035)], startPoint: .top, endPoint: .bottom)).frame(width: 212, height: 48)
                    Ellipse().fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.12), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 208, height: 35).offset(y: -8)
                        .overlay(Ellipse().stroke(Color.white.opacity(0.12), lineWidth: 0.7).offset(y: -8))
                    Ellipse().trim(from: 0.03, to: 0.47).stroke(MarsTheme.accent.opacity(max(0.08, lightLevel)), lineWidth: 1.2).frame(width: 208, height: 29).offset(y: 7)
                        .shadow(color: MarsTheme.accent.opacity(lightLevel * 0.3), radius: 5)
                    Ellipse().stroke(.black.opacity(0.5), lineWidth: 0.7).frame(width: 150, height: 25).offset(y: -8)
                }.offset(y: lifted ? -63 : -15)
            }
            .frame(width: 320, height: 300).scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeInOut(duration: 0.7), value: lifted)
        }
    }
}

struct RingMotif: View {
    var body: some View {
        ZStack {
            Ellipse().fill(MarsTheme.accent.opacity(0.025)).frame(width: 240, height: 100).blur(radius: 20)
            Ellipse().stroke(MarsTheme.line, lineWidth: 1).frame(width: 230, height: 92)
            Ellipse().stroke(MarsTheme.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.8, dash: [7,14])).frame(width: 230, height: 92)
            Ellipse().stroke(MarsTheme.line, lineWidth: 0.5).frame(width: 185, height: 70)
        }
    }
}

struct ConnectionHelpPage: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("连接控制") { Text("打开音箱后，进入设备列表并轻触 Mars。控制连接会保留，直到你主动断开或设备离线。") }
                Section("播放音乐") { Text("控制连接与音乐输出是两条通道。请在 iPhone 蓝牙设置连接音箱，再在音乐播放界面选择 Mars 作为输出设备。") }
                Section("悬浮升降") { Text("底座必须通电。将飞碟放到正确位置，再使用升起或降落。未能获取状态时，请以飞碟实际动作为准。") }
                Section("设备改名") { Text("保存后先降落，再将飞碟关机重开，并在 iPhone 蓝牙设置核对新名称。") }
            }
            .navigationTitle("连接与使用").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

private func liftDescription(_ value: Int?) -> String {
    guard let value else { return "状态待同步" }
    switch value {
    case 0,2,5: return "已降落"
    case 1,3,4: return "悬浮中"
    default: return "请观察飞碟状态"
    }
}

extension View {
    func marsBackground() -> some View {
        self.background(LinearGradient(colors: [Color(red: 0.063, green: 0.075, blue: 0.069), MarsTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
            .toolbarBackground(MarsTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
