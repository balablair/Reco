# Desktop Overlay 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 CreatorRecorder 的录制工作流（准备 → 录制 → 完成）从 Studio 窗口迁移到三个真实桌面 NSPanel 浮层：PrepBarPanel、RecHUDPanel、CompletionPanel。Studio 仅作为可选编辑器使用。

**架构：** `AppViewModel` 引入 `AppPhase` 枚举替代 `currentScreen`，三个 NSPanel 观察 `phase` 来显示/隐藏自身。所有浮层内容以 SwiftUI 视图实现，通过 `NSHostingView` 嵌入 `NSPanel`。

**技术栈：** Swift 6 + SwiftUI + AppKit (NSPanel) + `@Observable` + `withObservationTracking`

---

## 文件结构

### 新增文件

| 文件路径 | 职责 |
|---|---|
| `Sources/CreatorRecorder/Panels/FloatingPanelBase.swift` | 共享 NSPanel 基类（透明背景、floating level、无标题栏）|
| `Sources/CreatorRecorder/Panels/PrepBarPanel.swift` | PrepBar 的 NSPanel 管理器 + 显示/隐藏逻辑 |
| `Sources/CreatorRecorder/Panels/RecHUDPanel.swift` | RecHUD 的 NSPanel 管理器 |
| `Sources/CreatorRecorder/Panels/CompletionPanel.swift` | CompletionCard 的 NSPanel 管理器 |
| `Sources/CreatorRecorder/Panels/RecordingOutlinePanel.swift` | 录制区域红框透明窗口 |
| `Sources/CreatorRecorder/UI/PrepBarView.swift` | Prep Bar SwiftUI 视图（Liquid Glass 胶囊）|
| `Sources/CreatorRecorder/UI/RecHUDView.swift` | Rec HUD SwiftUI 视图（深色胶囊 + 计时器）|
| `Sources/CreatorRecorder/UI/CompletionCardView.swift` | Completion Card SwiftUI 视图（卡片 + 操作按钮）|

### 修改文件

| 文件路径 | 变更内容 |
|---|---|
| `Sources/CreatorRecorderKit/Models/Domain.swift` | 新增 `AppPhase` 枚举 |
| `Sources/CreatorRecorderKit/ViewModels/AppViewModel.swift` | 用 `phase: AppPhase` 替换 `currentScreen: Screen`；新增 `recordingElapsedSeconds`；修改 `startRecordingSession`/`stopRecordingSession` |
| `Sources/CreatorRecorder/CreatorRecorder.swift` | `AppRuntime` 改为管理三个 Panel；移除 `FloatingControlPanel`；改为 Overlay-first 启动；移除 `FloatingControlBarView` |
| `Sources/CreatorRecorder/UI/AppShellView.swift` | 移除 `preparation`/`recording` case，仅保留 `editor` |

---

## 任务一：AppPhase 枚举 + AppViewModel 状态重构

**文件：**
- 修改：`Sources/CreatorRecorderKit/Models/Domain.swift`
- 修改：`Sources/CreatorRecorderKit/ViewModels/AppViewModel.swift`

---

### 步骤 1.1：在 Domain.swift 中新增 AppPhase

找到 `Sources/CreatorRecorderKit/Models/Domain.swift` 中合适的位置（例如 `RecordingState` 枚举附近），添加：

```swift
public enum AppPhase: Equatable {
    case preparation
    case recording
    case completion
    case editing
}
```

---

### 步骤 1.2：在 AppViewModel 中替换 currentScreen

**当前代码（AppViewModel.swift:10-18）：**
```swift
public enum Screen: String, CaseIterable, Identifiable {
    case preparation
    case recording
    case editor
    public var id: String { rawValue }
}
public var currentScreen: Screen = .preparation
```

**替换为：**
```swift
public var phase: AppPhase = .preparation
```

同时删除 `select(screen:)` 方法（第 50-59 行），新增：
```swift
public func transitionToPhase(_ newPhase: AppPhase) {
    guard !isRecordingActive || newPhase == .recording else { return }
    phase = newPhase
}
```

---

### 步骤 1.3：修改 startRecordingSession()

**当前代码（AppViewModel.swift:254-269）：**
```swift
public func startRecordingSession() {
    guard !isRecordingActive else { return }
    recordingState = .recording
    currentScreen = .recording
    let configuration = makeCaptureSessionConfiguration()
    Task { @MainActor in
        do {
            try await captureService.start(configuration: configuration)
        } catch {
            self.recordingState = .failed(error.localizedDescription)
            self.currentScreen = .preparation
        }
    }
}
```

**替换为：**
```swift
public func startRecordingSession() {
    guard !isRecordingActive else { return }
    recordingState = .recording
    phase = .recording
    startElapsedTimer()
    let configuration = makeCaptureSessionConfiguration()
    Task { @MainActor in
        do {
            try await captureService.start(configuration: configuration)
        } catch {
            self.recordingState = .failed(error.localizedDescription)
            self.phase = .preparation
            self.stopElapsedTimer()
        }
    }
}
```

---

### 步骤 1.4：修改 stopRecordingSession()

**当前代码（AppViewModel.swift:271-279）：**
```swift
public func stopRecordingSession() async {
    guard isRecordingActive else { return }
    recordingState = .idle
    currentScreen = .editor         // ← 需要改为 .completion
    latestRecording = await captureService.stop()
    playbackState = .paused
    playbackPositionSeconds = 0
}
```

**替换为：**
```swift
public func stopRecordingSession() async {
    guard isRecordingActive else { return }
    recordingState = .idle
    phase = .completion
    stopElapsedTimer()
    latestRecording = await captureService.stop()
    playbackState = .paused
    playbackPositionSeconds = 0
}
```

---

### 步骤 1.5：新增录制计时器

在 `AppViewModel` 的属性区域新增：
```swift
public var recordingElapsedSeconds: Int = 0
private var elapsedTimer: Timer?
```

新增私有方法：
```swift
private func startElapsedTimer() {
    recordingElapsedSeconds = 0
    elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            self?.recordingElapsedSeconds += 1
        }
    }
}

private func stopElapsedTimer() {
    elapsedTimer?.invalidate()
    elapsedTimer = nil
}
```

还需在 `AppViewModel` 中新增一个计算属性供 HUD 显示：
```swift
public var recordingElapsedLabel: String {
    let m = recordingElapsedSeconds / 60
    let s = recordingElapsedSeconds % 60
    return String(format: "%02d:%02d", m, s)
}
```

---

### 步骤 1.6：新增 Redo 和 openInStudio 方法

```swift
public func redo() {
    guard phase == .completion else { return }
    latestRecording = nil
    recordingElapsedSeconds = 0
    exportState = .idle
    phase = .preparation
}

public func openInStudio() {
    phase = .editing
}
```

---

### 步骤 1.7：修复 AppShellView.swift 编译错误

`AppShellView.swift` 中的 `switch viewModel.currentScreen` 需要改为使用 `phase`。

**当前代码（AppShellView.swift:33-41）：**
```swift
switch viewModel.currentScreen {
case .preparation:
    PreparationScreenView(viewModel: viewModel)
case .recording:
    RecordingScreenView(viewModel: viewModel)
case .editor:
    EditorScreenView(viewModel: viewModel)
}
```

**替换为（只保留 editor，其余由 Panel 处理）：**
```swift
switch viewModel.phase {
case .editing:
    EditorScreenView(viewModel: viewModel)
default:
    EditorScreenView(viewModel: viewModel)
        .hidden()
}
```

同时将 `AppShellView.swift:15` 中的 `viewModel.currentScreen == .editor` 改为 `viewModel.phase == .editing`，第 21 行同理。

---

### 步骤 1.8：编译验证

```bash
cd /Users/balablair/Desktop/CreatorRecorder
swift build 2>&1 | head -50
```

预期：编译成功（或仅有 Panel 相关的"文件不存在"错误）。

---

## 任务二：FloatingPanelBase 共享基类

**文件：**
- 创建：`Sources/CreatorRecorder/Panels/FloatingPanelBase.swift`

---

### 步骤 2.1：创建 FloatingPanelBase.swift

```swift
import AppKit
import SwiftUI

/// 所有 Overlay Panel 的共享基类 NSPanel
@MainActor
class FloatingPanelBase: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
    }

    func show(at origin: CGPoint) {
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
```

---

## 任务三：PrepBarPanel（Prep Bar 面板）

**文件：**
- 创建：`Sources/CreatorRecorder/UI/PrepBarView.swift`
- 创建：`Sources/CreatorRecorder/Panels/PrepBarPanel.swift`

---

### 步骤 3.1：创建 PrepBarView.swift

实现设计规格中的 Prep Bar 布局（Liquid Glass 胶囊）：

```swift
import SwiftUI
import CreatorRecorderKit

struct PrepBarView: View {
    @Bindable var viewModel: AppViewModel
    let onRecord: () -> Void
    let onPickArea: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 状态点
            Circle()
                .fill(Color(hex: "#28cd41"))
                .frame(width: 8, height: 8)

            // 区域尺寸标签
            Text(viewModel.captureRegionLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .monospacedDigit()

            separator

            // 功能 chips
            chipButton(
                icon: cameraIcon,
                active: viewModel.overlayState.cameraVisible
            ) {
                viewModel.toggleCameraOverlay()
            }

            chipButton(
                icon: teleprompterIcon,
                active: viewModel.overlayState.teleprompterVisible
            ) {
                viewModel.toggleTeleprompterOverlay()
            }

            chipButton(
                icon: micIcon,
                active: viewModel.overlayState.microphoneEnabled
            ) {
                viewModel.toggleMicrophone()
            }

            chipButton(
                icon: pickAreaIcon,
                active: false
            ) {
                onPickArea()
            }

            separator

            // Record CTA
            Button(action: onRecord) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#ff3b30"))
                        .frame(width: 8, height: 8)
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Color.black.opacity(0.82))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .background(glassBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 10)
        .contextMenu {
            Button("Quit CreatorRecorder") { onQuit() }
        }
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
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill(Color.white.opacity(0.25)))
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

    private var teleprompterIcon: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 14, weight: .medium))
    }

    private var micIcon: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 14, weight: .medium))
    }

    private var pickAreaIcon: some View {
        Image(systemName: "crop")
            .font(.system(size: 14, weight: .medium))
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
```

---

### 步骤 3.2：创建 PrepBarPanel.swift

```swift
import AppKit
import SwiftUI
import CreatorRecorderKit

@MainActor
final class PrepBarPanel: NSObject, NSWindowDelegate {
    static let shared = PrepBarPanel()

    private var window: FloatingPanelBase?
    private let preferredSize = CGSize(width: 430, height: 58)

    private override init() {}

    func show(
        viewModel: AppViewModel,
        onRecord: @escaping () -> Void,
        onPickArea: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        if let window {
            if let hosting = window.contentView as? NSHostingView<PrepBarView> {
                hosting.rootView = PrepBarView(
                    viewModel: viewModel,
                    onRecord: onRecord,
                    onPickArea: onPickArea,
                    onQuit: onQuit
                )
            }
            window.orderFrontRegardless()
            return
        }

        let rootView = PrepBarView(
            viewModel: viewModel,
            onRecord: onRecord,
            onPickArea: onPickArea,
            onQuit: onQuit
        )
        let origin = defaultOrigin()
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func defaultOrigin() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 400, y: 80)
        }
        let frame = screen.visibleFrame
        let x = frame.midX - preferredSize.width / 2
        let y = frame.minY + 60
        return CGPoint(x: x, y: y)
    }
}
```

---

### 步骤 3.3：编译验证

```bash
cd /Users/balablair/Desktop/CreatorRecorder
swift build 2>&1 | grep -E "error:|warning:" | head -30
```

---

## 任务四：RecHUDPanel（录制 HUD 面板）

**文件：**
- 创建：`Sources/CreatorRecorder/UI/RecHUDView.swift`
- 创建：`Sources/CreatorRecorder/Panels/RecHUDPanel.swift`
- 创建：`Sources/CreatorRecorder/Panels/RecordingOutlinePanel.swift`

---

### 步骤 4.1：创建 RecHUDView.swift

```swift
import SwiftUI
import CreatorRecorderKit

struct RecHUDView: View {
    @Bindable var viewModel: AppViewModel
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // REC 指示器
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#ff453a"))
                    .frame(width: 8, height: 8)
                    .opacity(blinkOpacity)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: blinkOpacity)
                    .onAppear { blinkOpacity = 0.3 }

                Text("REC")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#ff453a"))
            }

            // 计时器
            Text(viewModel.recordingElapsedLabel)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.85))

            hudSeparator

            // Stop 按钮
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.18)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(darkGlassBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    @State private var blinkOpacity: Double = 1.0

    private var hudSeparator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var darkGlassBackground: some View {
        Rectangle()
            .fill(Color(red: 28/255, green: 28/255, blue: 30/255).opacity(0.78))
            .overlay(Rectangle().fill(.ultraThinMaterial.opacity(0.2)))
    }
}

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
```

---

### 步骤 4.2：创建 RecordingOutlinePanel.swift

```swift
import AppKit
import SwiftUI

/// 录制区域红框透明覆盖窗口，不拦截鼠标事件
@MainActor
final class RecordingOutlinePanel: NSObject {
    static let shared = RecordingOutlinePanel()

    private var window: NSPanel?

    private override init() {}

    func show(frame: CGRect) {
        hide()
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let outline = NSHostingView(rootView: RecordingOutlineView())
        panel.contentView = outline
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

private struct RecordingOutlineView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color(red: 1, green: 0.23, blue: 0.19).opacity(0.9), lineWidth: 1.5)
            .ignoresSafeArea()
    }
}
```

---

### 步骤 4.3：创建 RecHUDPanel.swift

```swift
import AppKit
import SwiftUI
import CreatorRecorderKit

@MainActor
final class RecHUDPanel: NSObject {
    static let shared = RecHUDPanel()

    private var window: FloatingPanelBase?
    private let preferredSize = CGSize(width: 220, height: 48)

    private override init() {}

    func show(viewModel: AppViewModel, captureFrame: CGRect, onStop: @escaping () -> Void) {
        if let window, let hosting = window.contentView as? NSHostingView<RecHUDView> {
            hosting.rootView = RecHUDView(viewModel: viewModel, onStop: onStop)
            window.orderFrontRegardless()
            return
        }

        let rootView = RecHUDView(viewModel: viewModel, onStop: onStop)
        let origin = hudOrigin(above: captureFrame)
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// 将 HUD 放在录制区域顶部居中
    private func hudOrigin(above captureFrame: CGRect) -> CGPoint {
        let x = captureFrame.midX - preferredSize.width / 2
        let y = captureFrame.maxY + 12
        return CGPoint(x: x, y: y)
    }
}
```

---

## 任务五：CompletionPanel（完成卡片面板）

**文件：**
- 创建：`Sources/CreatorRecorder/UI/CompletionCardView.swift`
- 创建：`Sources/CreatorRecorder/Panels/CompletionPanel.swift`

---

### 步骤 5.1：创建 CompletionCardView.swift

```swift
import SwiftUI
import CreatorRecorderKit

struct CompletionCardView: View {
    @Bindable var viewModel: AppViewModel
    let onRedo: () -> Void
    let onTrim: () -> Void
    let onShare: () -> Void
    let onOpenInStudio: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // 缩略图
            thumbnailView

            // 元数据
            HStack {
                Text(metaLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer()
            }

            // 次要操作
            HStack(spacing: 8) {
                secondaryButton(label: "Redo", systemImage: "arrow.uturn.left") { onRedo() }
                secondaryButton(label: "Trim", systemImage: "scissors") { onTrim() }
                secondaryButton(label: "Share", systemImage: "square.and.arrow.up") { onShare() }
            }

            // 主操作
            Button(action: onOpenInStudio) {
                HStack {
                    Text("Open in Studio")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 310)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 32, y: 12)
    }

    // MARK: - Sub-components

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(height: 80)

            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.38))
        }
    }

    private var cardBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill(Color.white.opacity(0.3)))
    }

    @ViewBuilder
    private func secondaryButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.06)))
            .foregroundStyle(Color.black.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private var metaLabel: String {
        let duration = viewModel.formatPlaybackTime(Double(viewModel.recordingElapsedSeconds))
        if let recording = viewModel.latestRecording {
            let mb = recording.fileSizeBytes / 1_000_000
            return "\(duration) · \(mb) MB"
        }
        return duration
    }
}
```

> **注意**：`RecordingResult` 可能没有 `fileSizeBytes` 属性——如果没有，`metaLabel` 简化为只显示时长。

---

### 步骤 5.2：创建 CompletionPanel.swift

```swift
import AppKit
import SwiftUI
import CreatorRecorderKit

@MainActor
final class CompletionPanel: NSObject {
    static let shared = CompletionPanel()

    private var _window: FloatingPanelBase?
    /// 供 AppRuntime 的 shareRecording() 使用
    var window: FloatingPanelBase? { _window }
    private let preferredSize = CGSize(width: 310, height: 260)

    private override init() {}

    func show(
        viewModel: AppViewModel,
        onRedo: @escaping () -> Void,
        onTrim: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onOpenInStudio: @escaping () -> Void
    ) {
        if let _window, let hosting = _window.contentView as? NSHostingView<CompletionCardView> {
            hosting.rootView = CompletionCardView(
                viewModel: viewModel,
                onRedo: onRedo,
                onTrim: onTrim,
                onShare: onShare,
                onOpenInStudio: onOpenInStudio
            )
            window.orderFrontRegardless()
            return
        }

        let rootView = CompletionCardView(
            viewModel: viewModel,
            onRedo: onRedo,
            onTrim: onTrim,
            onShare: onShare,
            onOpenInStudio: onOpenInStudio
        )
        let origin = defaultOrigin()
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        self._window = panel
    }

    func hide() {
        _window?.orderOut(nil)
    }

    private func defaultOrigin() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 100, y: 100)
        }
        let frame = screen.visibleFrame
        let x = frame.maxX - preferredSize.width - 24
        let y = frame.minY + 24
        return CGPoint(x: x, y: y)
    }
}
```

---

## 任务六：AppRuntime 重构

**文件：**
- 修改：`Sources/CreatorRecorder/CreatorRecorder.swift`

---

### 步骤 6.1：重构 AppRuntime

将 `AppRuntime` 的 `launch()` 方法从 `FloatingControlPanel` 切换到三 Panel 架构：

**替换当前 `AppRuntime` 类（第 268-354 行）：**

```swift
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let viewModel = AppViewModel()

    private lazy var studioWindowController = StudioWindowController(viewModel: viewModel)

    private init() {}

    func launch() {
        NSApp.setActivationPolicy(.accessory)
        observePhase()

        Task { @MainActor [weak self] in
            await self?.viewModel.bootstrap()
            self?.showPrepBar()
        }
    }

    // MARK: - Phase observation

    private func observePhase() {
        withObservationTracking {
            _ = viewModel.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handlePhaseChange()
                self?.observePhase()
            }
        }
    }

    private func handlePhaseChange() {
        switch viewModel.phase {
        case .preparation:
            RecHUDPanel.shared.hide()
            RecordingOutlinePanel.shared.hide()
            CompletionPanel.shared.hide()
            showPrepBar()

        case .recording:
            PrepBarPanel.shared.hide()
            CompletionPanel.shared.hide()
            let captureFrame = captureScreenFrame()
            RecordingOutlinePanel.shared.show(frame: captureFrame)
            RecHUDPanel.shared.show(viewModel: viewModel, captureFrame: captureFrame) { [weak self] in
                self?.stopRecording()
            }

        case .completion:
            RecHUDPanel.shared.hide()
            RecordingOutlinePanel.shared.hide()
            PrepBarPanel.shared.hide()
            showCompletion()

        case .editing:
            CompletionPanel.shared.hide()
            studioWindowController.showStudio()
        }
    }

    // MARK: - Show helpers

    private func showPrepBar() {
        PrepBarPanel.shared.show(
            viewModel: viewModel,
            onRecord: { [weak self] in
                self?.viewModel.startRecordingSession()
            },
            onPickArea: { [weak self] in
                self?.startRegionPicker()
            },
            onQuit: { [weak self] in
                self?.terminate()
            }
        )
    }

    private func showCompletion() {
        CompletionPanel.shared.show(
            viewModel: viewModel,
            onRedo: { [weak self] in
                self?.viewModel.redo()
            },
            onTrim: { [weak self] in
                self?.viewModel.openInStudio()
            },
            onShare: { [weak self] in
                self?.shareRecording()
            },
            onOpenInStudio: { [weak self] in
                self?.viewModel.openInStudio()
            }
        )
    }

    // MARK: - Actions

    private func stopRecording() {
        Task { await viewModel.stopRecordingSession() }
    }

    private func startRegionPicker() {
        PrepBarPanel.shared.hide()
        viewModel.setRegionSelection(active: true)
        DesktopRegionPicker.shared.begin(
            on: viewModel.selectedDisplaySource,
            onSelection: { [weak self] rect in
                self?.viewModel.applyScreenSelection(rect)
                self?.viewModel.setRegionSelection(active: false)
                self?.showPrepBar()
            },
            onCancel: { [weak self] in
                self?.viewModel.setRegionSelection(active: false)
                self?.showPrepBar()
            }
        )
    }

    private func shareRecording() {
        guard let url = viewModel.latestRecording?.fileURL else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let window = CompletionPanel.shared.window {
            picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
        }
    }

    // MARK: - Capture frame

    private func captureScreenFrame() -> CGRect {
        // 将 captureRegion 转换为屏幕坐标
        guard let screen = NSScreen.main else {
            return CGRect(x: 100, y: 100, width: 1280, height: 720)
        }
        let region = viewModel.captureRegion
        let screenHeight = screen.frame.height
        // captureRegion 使用 AppKit 坐标系（原点在左下）
        return CGRect(
            x: region.origin.x,
            y: screenHeight - region.origin.y - region.size.height,
            width: region.size.width,
            height: region.size.height
        )
    }

    func terminate() {
        Task {
            if viewModel.isRecordingActive {
                await viewModel.stopRecordingSession()
            }
            NSApp.terminate(nil)
        }
    }
}
```

---

### 步骤 6.2：Share 功能简化处理

`CompletionPanel.swift`（步骤 5.2）已使用 `_window` + 公开计算属性 `window` 的模式，`AppRuntime.shareRecording()` 可直接访问 `CompletionPanel.shared.window`。

如果 `NSSharingServicePicker` 实现复杂，可以先简化为：
```swift
private func shareRecording() {
    guard let url = viewModel.latestRecording?.fileURL else { return }
    NSWorkspace.shared.open(url)
}
```

---

### 步骤 6.3：删除 FloatingControlPanel 和 FloatingControlBarView

从 `CreatorRecorder.swift` 中删除（第 119-222 行的 `FloatingControlPanel` 类 和第 371-445 行的 `FloatingControlBarView` 结构体），因为这些已被 PrepBarPanel/RecHUDPanel 取代。

---

### 步骤 6.4：编译验证

```bash
cd /Users/balablair/Desktop/CreatorRecorder
swift build 2>&1 | grep "error:" | head -30
```

预期：0 个 error。

---

## 任务七：端到端手动测试

```bash
cd /Users/balablair/Desktop/CreatorRecorder
swift run
```

测试检查表：
- [ ] 应用启动后，PrepBar 显示在屏幕底部
- [ ] 点击 Camera/Mic/Teleprompter chip，图标状态切换
- [ ] 点击 Pick Area，选区覆盖层出现，PrepBar 隐藏
- [ ] 完成选区后，PrepBar 重新显示，尺寸更新
- [ ] 点击 Record，PrepBar 消失，RecHUD 显示，录制区红框出现
- [ ] 计时器每秒递增
- [ ] 点击 Stop，RecHUD 消失，红框消失，CompletionCard 显示在右下角
- [ ] 点击 Redo，CompletionCard 消失，PrepBar 重新显示
- [ ] 点击 Open in Studio，Studio 窗口打开
- [ ] 右键 PrepBar 上下文菜单可以 Quit

---

## 注意事项

1. **`RecordingResult.fileSizeBytes`**：如果该属性不存在，在 `CompletionCardView.metaLabel` 中只显示时长，跳过 MB 显示。
2. **`captureRegion` 坐标系**：需要确认 `CaptureRegion.origin` 是 AppKit 坐标系还是 CGWindowLevel 坐标系，如果有偏差，`RecordingOutlinePanel` 的位置需要调整。
3. **`Color(hex:)` 扩展重复**：`PrepBarView.swift` 和 `RecHUDView.swift` 都定义了 `private extension Color { init(hex:) }`，这不会冲突（private scope），但可以考虑提取到共享的 `Sources/CreatorRecorder/UI/DesignTokens.swift` 文件中。
4. **`blinkOpacity` 动画**：`RecHUDView` 的 `@State private var blinkOpacity: Double = 1.0` 需要在 `.onAppear` 中触发初始动画：`.onAppear { blinkOpacity = 0.3 }`
