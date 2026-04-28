import SwiftUI
import AVFoundation
import ScreenCaptureKit
import RecoKit

struct PrepBarView: View {
    @Bindable var viewModel: AppViewModel
    @Bindable var actions: PrepBarActions

    @State private var showTeleprompterEditor = false
    @State private var showBeautyPanel = false
    @State private var showPermissionPopover = false
    @State private var cameraAuthStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// 系统录音权限：nil=未知，true=已授权，false=被拒
    @State private var systemAudioAuthGranted: Bool? = nil
    /// 录屏权限：nil=未知，true=已授权，false=被拒
    @State private var screenCaptureGranted: Bool? = nil

    var body: some View {
        HStack(spacing: 10) {
            // 状态点（绿色=屏幕区域，蓝色=窗口模式）
            Circle()
                .fill(viewModel.selectedWindowSource != nil
                      ? Color(hex: "#007aff")
                      : Color(hex: "#28cd41"))
                .frame(width: 8, height: 8)

            // 捕获源标签（区域尺寸 或 窗口名称）
            sourceLabel

            separator

            // 功能 chips
            if cameraAuthStatus == .denied {
                // 权限被拒绝：显示红色相机斜线图标，点击跳转系统设置
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "camera.slash.fill")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("摄像头权限被拒绝，点击前往系统设置开启")
            } else {
                chipButton(
                    icon: cameraIcon,
                    active: viewModel.overlayState.cameraVisible
                ) {
                    viewModel.toggleCameraOverlay()
                }
            }

            // 美颜 / 灯光按钮
            chipButton(
                icon: beautyIcon,
                active: !viewModel.cameraBeauty.isDefault
            ) {
                showBeautyPanel = true
            }
            .popover(isPresented: $showBeautyPanel, arrowEdge: .bottom) {
                BeautyControlSheet(viewModel: viewModel)
            }

            // 提词器按钮 + 编辑 Popover
            chipButton(
                icon: teleprompterIcon,
                active: viewModel.overlayState.teleprompterVisible || !viewModel.teleprompterText.isEmpty
            ) {
                showTeleprompterEditor = true
            }
            .popover(isPresented: $showTeleprompterEditor, arrowEdge: .bottom) {
                TeleprompterEditSheet(viewModel: viewModel)
            }

            chipButton(
                icon: micIcon,
                active: viewModel.overlayState.microphoneEnabled
            ) {
                viewModel.toggleMicrophone()
            }

            // 系统声音按钮：权限被拒时变红并点击跳转设置
            if systemAudioAuthGranted == false {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("系统录音权限被拒绝，点击前往系统设置 → 隐私与安全性 → 录屏与系统录音，开启「仅系统录音」")
            } else {
                chipButton(
                    icon: systemAudioIcon,
                    active: viewModel.overlayState.systemAudioEnabled
                ) {
                    // 开启时检查权限
                    if !viewModel.overlayState.systemAudioEnabled {
                        Task { await checkSystemAudioPermission() }
                    }
                    viewModel.toggleSystemAudio()
                }
                .help(viewModel.overlayState.systemAudioEnabled ? "系统声音：开启" : "系统声音：关闭")
            }

            // 捕获源选择按钮（区域 + 窗口列表）
            sourcePickerMenu

            separator

            // 录屏权限警告（仅在录屏明确被拒时显示，摄像头由上面的红色相机图标处理）
            if screenCaptureGranted == false {
                Button {
                    showPermissionPopover = true
                } label: {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.orange.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("录屏权限未开启，点击查看详情")
                .popover(isPresented: $showPermissionPopover, arrowEdge: .bottom) {
                    PermissionBanner(
                        screenGranted: false,
                        cameraGranted: true,
                        onFixScreen: {
                            showPermissionPopover = false
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        onFixCamera: { }
                    )
                    .frame(width: 240)
                }
            }

            // Record CTA
            Button(action: { actions.onRecord() }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#ff3b30"))
                        .frame(width: 8, height: 8)
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .fixedSize()
        .background(glassBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 10)
        .contextMenu {
            Button("Quit Reco") { actions.onQuit() }
        }
        .task {
            await checkPermissions()
        }
    }

    // MARK: - Permission checks

    /// 静默检查权限状态（仅用于更新 UI 指示，不阻断任何操作）
    private func checkPermissions() async {
        // 用 CGPreflightScreenCaptureAccess 直接查 TCC，不受 ad-hoc 签名影响
        let granted = CGPreflightScreenCaptureAccess()
        NSLog("[PrepBar] CGPreflightScreenCaptureAccess = %d", granted ? 1 : 0)
        screenCaptureGranted = granted
        systemAudioAuthGranted = granted
        // 同步更新摄像头权限状态
        cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func checkSystemAudioPermission() async {
        await checkPermissions()
    }

    // MARK: - Source label

    @ViewBuilder
    private var sourceLabel: some View {
        if let win = viewModel.selectedWindowSource {
            // 窗口模式：显示 App 名称（截断）
            Text(win.appName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
        } else {
            Text(viewModel.captureRegionLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .monospacedDigit()
        }
    }

    // MARK: - Source picker menu

    @ViewBuilder
    private var sourcePickerMenu: some View {
        Menu {
            // 自定义选区
            Button {
                viewModel.selectWindowSource(nil)
                actions.onPickArea()
            } label: {
                Label("自定义选区", systemImage: "crop")
            }

            if !viewModel.availableWindows.isEmpty {
                Divider()
                // 按 App 名称分组显示窗口
                let grouped = Dictionary(grouping: viewModel.availableWindows, by: \.appName)
                let sortedApps = grouped.keys.sorted()
                ForEach(sortedApps, id: \.self) { appName in
                    let wins = grouped[appName] ?? []
                    if wins.count == 1, let win = wins.first {
                        Button {
                            viewModel.selectWindowSource(win)
                        } label: {
                            HStack {
                                Label(win.displayName, systemImage: "macwindow")
                                if viewModel.selectedWindowSource?.id == win.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } else {
                        // 多个窗口来自同一 App
                        Menu(appName) {
                            ForEach(wins) { win in
                                Button {
                                    viewModel.selectWindowSource(win)
                                } label: {
                                    let title = win.windowTitle.isEmpty ? win.appName : win.windowTitle
                                    HStack {
                                        Label(title, systemImage: "macwindow")
                                        if viewModel.selectedWindowSource?.id == win.id {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Divider()
            // 刷新窗口列表
            Button {
                Task { await viewModel.refreshWindows() }
            } label: {
                Label("刷新窗口列表", systemImage: "arrow.clockwise")
            }
        } label: {
            pickAreaIcon
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(viewModel.selectedWindowSource != nil
                                  ? Color.blue.opacity(0.12)
                                  : Color.clear)
                )
                .foregroundStyle(viewModel.selectedWindowSource != nil
                                 ? Color.blue.opacity(0.85)
                                 : Color.black.opacity(0.55))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Sub-components

    private var separator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 20)
            .padding(.horizontal, 6)
    }

    private var glassBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(Capsule().fill(Color.white.opacity(0.25)))
    }

    @ViewBuilder
    private func chipButton(icon: some View, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(active ? Color.black.opacity(0.08) : Color.clear)
                )
                .foregroundStyle(active ? Color.black.opacity(0.85) : Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icons (SF Symbols)

    private var cameraIcon: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 14, weight: .medium))
    }

    private var beautyIcon: some View {
        Image(systemName: "wand.and.sparkles")
            .font(.system(size: 14, weight: .medium))
    }

    private var teleprompterIcon: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 14, weight: .medium))
    }

    private var micIcon: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 14, weight: .medium))
    }

    private var systemAudioIcon: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 14, weight: .medium))
    }

    private var pickAreaIcon: some View {
        Image(systemName: "crop")
            .font(.system(size: 14, weight: .medium))
    }
}

// MARK: - 美颜 & 灯光控制面板

struct BeautyControlSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("美颜 & 灯光")
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Button {
                    viewModel.cameraBeauty = .default
                    viewModel.savePreferences()
                } label: {
                    Text("重置")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(viewModel.cameraBeauty.isDefault ? 0 : 1)

                Button("完成") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.5)

            VStack(spacing: 16) {
                // 磨皮
                beautyRow(
                    icon: "face.smiling",
                    iconColor: .pink,
                    label: "磨皮",
                    value: $viewModel.cameraBeauty.smoothing,
                    range: 0...1,
                    format: { "\(Int($0 * 100))%" }
                )

                // 补光（曝光）
                beautyRow(
                    icon: "sun.max.fill",
                    iconColor: .yellow,
                    label: "补光",
                    value: $viewModel.cameraBeauty.exposure,
                    range: -1...1,
                    format: { $0 == 0 ? "0" : String(format: "%+.1f", $0) }
                )

                // 亮度
                beautyRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: .gray,
                    label: "亮度",
                    value: $viewModel.cameraBeauty.brightness,
                    range: -0.5...0.5,
                    format: { $0 == 0 ? "0" : String(format: "%+.2f", $0) }
                )

                // 色温（暖色）
                beautyRow(
                    icon: "thermometer.medium",
                    iconColor: .orange,
                    label: "暖色",
                    value: $viewModel.cameraBeauty.warmth,
                    range: -2000...2000,
                    format: { $0 == 0 ? "0K" : String(format: "%+.0fK", $0) }
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(width: 320)
        .onChange(of: viewModel.cameraBeauty) { _, _ in
            viewModel.savePreferences()
        }
    }

    private func beautyRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            Slider(value: value, in: range)
                .tint(iconColor)
        }
    }
}

// 便捷颜色初始化
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
