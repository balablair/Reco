import AppKit
import Observation
import SwiftUI
import CreatorRecorderKit

private enum RuntimeConstants {
    static let floatingPanelSize = CGSize(width: 372, height: 112)
    static let floatingPanelDefaultOrigin = CGPoint(x: 120, y: 120)
    static let floatingPanelSnapDistance: CGFloat = 24
    static let floatingPanelOriginDefaultsKey = "CreatorRecorder.floatingPanelOrigin"
    static let fallbackVisibleFrame = CGRect(x: 80, y: 80, width: 1440, height: 900)
}

@MainActor
final class DesktopRegionPickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopRegionPicker: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopRegionPicker()

    private let configuration = DesktopRegionPickerConfiguration.interactiveOverlay
    private var overlayWindow: NSWindow?
    private var onSelection: ((CGRect) -> Void)?
    private var onCancel: (() -> Void)?
    private var session = DesktopRegionPickerSession()

    func begin(on display: DisplaySource, onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void = {}) {
        closeOverlay()
        _ = session.begin()
        self.onSelection = onSelection
        self.onCancel = onCancel

        let contentView = DesktopRegionPickerOverlay(
            displayFrame: display.frame,
            cancelsOnEscape: configuration.cancelsOnEscape,
            onCommit: { [weak self] rect in
                self?.finishSelection(rect)
            },
            onCancel: { [weak self] in
                self?.cancelSelection()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let window = DesktopRegionPickerWindow(
            contentRect: display.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovable = false
        window.delegate = self
        if configuration.activatesApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        if configuration.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        overlayWindow = window
    }

    private func finishSelection(_ rect: CGRect) {
        session.finish()
        let onSelection = self.onSelection
        closeOverlay()
        onSelection?(rect)
    }

    private func cancelSelection() {
        session.finish()
        let onCancel = self.onCancel
        closeOverlay()
        onCancel?()
    }

    func windowDidResignKey(_ notification: Notification) {
        _ = notification
        guard session.overlayDidResignActive() == .cancel else { return }
        cancelSelection()
    }

    private func closeOverlay() {
        overlayWindow?.delegate = nil
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
        onSelection = nil
        onCancel = nil
    }
}

@MainActor
final class FloatingPanelWindow: NSPanel {
    var onPointerUp: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseUp {
            onPointerUp?()
        }
    }
}

@MainActor
final class FloatingControlPanel: NSObject, NSWindowDelegate {
    static let shared = FloatingControlPanel()

    private var window: FloatingPanelWindow?

    func show(viewModel: AppViewModel, onOpenStudio: @escaping () -> Void, onQuit: @escaping () -> Void) {
        let rootView = FloatingControlBarView(viewModel: viewModel, onOpenStudio: onOpenStudio, onQuit: onQuit)

        if let window, let hostingView = window.contentView as? NSHostingView<FloatingControlBarView> {
            hostingView.rootView = rootView
            let origin = restoredOrigin(for: window)
            window.setFrameOrigin(origin)
            persistWindowOrigin(origin)
            window.orderFrontRegardless()
            return
        }

        let hostingView = NSHostingView(rootView: rootView)
        let frame = CGRect(origin: RuntimeConstants.floatingPanelDefaultOrigin, size: RuntimeConstants.floatingPanelSize)
        let window = FloatingPanelWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.delegate = self
        window.onPointerUp = { [weak self] in
            self?.snapWindowIfNeeded(animated: true)
        }

        let origin = restoredOrigin(for: window)
        window.setFrameOrigin(origin)
        persistWindowOrigin(origin)
        window.orderFrontRegardless()
        self.window = window
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistWindowOrigin(window.frame.origin)
    }

    private func snapWindowIfNeeded(animated: Bool) {
        guard let window else { return }
        let visibleFrame = visibleFrame(for: window)
        let targetOrigin = FloatingPanelPlacement.snappedOrigin(
            proposedOrigin: window.frame.origin,
            panelSize: window.frame.size,
            visibleFrame: visibleFrame,
            snapDistance: RuntimeConstants.floatingPanelSnapDistance
        )
        guard targetOrigin != window.frame.origin else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                window.animator().setFrameOrigin(targetOrigin)
            }
        } else {
            window.setFrameOrigin(targetOrigin)
        }

        persistWindowOrigin(targetOrigin)
    }

    private func restoredOrigin(for window: NSWindow) -> CGPoint {
        let visibleFrame = visibleFrame(for: window)
        let storedOrigin = loadStoredOrigin() ?? RuntimeConstants.floatingPanelDefaultOrigin
        return FloatingPanelPlacement.restoredOrigin(
            storedOrigin: storedOrigin,
            panelSize: window.frame.size,
            visibleFrame: visibleFrame
        )
    }

    private func visibleFrame(for window: NSWindow) -> CGRect {
        window.screen?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? RuntimeConstants.fallbackVisibleFrame
    }

    private func loadStoredOrigin() -> CGPoint? {
        guard
            let values = UserDefaults.standard.array(forKey: RuntimeConstants.floatingPanelOriginDefaultsKey) as? [Double],
            values.count == 2
        else {
            return nil
        }
        return CGPoint(x: values[0], y: values[1])
    }

    private func persistWindowOrigin(_ origin: CGPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: RuntimeConstants.floatingPanelOriginDefaultsKey)
    }
}

@MainActor
final class StudioWindowController: NSWindowController, NSWindowDelegate {
    init(viewModel: AppViewModel) {
        let hostingView = NSHostingView(rootView: AppShellView(viewModel: viewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 180, width: 1440, height: 960),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CreatorRecorder Studio"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true && window?.isMiniaturized != true
    }

    func showStudio() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideStudio() {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let viewModel = AppViewModel()

    private lazy var studioWindowController = StudioWindowController(viewModel: viewModel)
    private var studioVisibilityState = StudioWindowVisibilityState()
    private var lastRecordingActive = false

    private init() {}

    func launch() {
        NSApp.setActivationPolicy(.accessory)
        lastRecordingActive = viewModel.isRecordingActive
        observeRecordingState()
        FloatingControlPanel.shared.show(
            viewModel: viewModel,
            onOpenStudio: { [weak self] in
                self?.showStudioIfAvailable()
            },
            onQuit: { [weak self] in
                self?.terminate()
            }
        )

        Task { @MainActor [weak self] in
            await self?.viewModel.bootstrap()
            guard let self else { return }
            FloatingControlPanel.shared.show(
                viewModel: self.viewModel,
                onOpenStudio: { [weak self] in
                    self?.showStudioIfAvailable()
                },
                onQuit: { [weak self] in
                    self?.terminate()
                }
            )
        }
    }

    private func observeRecordingState() {
        withObservationTracking {
            _ = viewModel.recordingState
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleRecordingStateChange()
                self?.observeRecordingState()
            }
        }
    }

    private func handleRecordingStateChange() {
        let isRecordingActive = viewModel.isRecordingActive
        guard isRecordingActive != lastRecordingActive else { return }
        lastRecordingActive = isRecordingActive

        if isRecordingActive {
            switch studioVisibilityState.recordingDidStart(studioIsVisible: studioWindowController.isVisible) {
            case .hide:
                studioWindowController.hideStudio()
            case .none, .show:
                break
            }
        } else {
            switch studioVisibilityState.recordingDidEnd() {
            case .show:
                studioWindowController.showStudio()
            case .none, .hide:
                break
            }
        }
    }

    func showStudioIfAvailable() {
        guard !viewModel.isRecordingActive else { return }
        studioWindowController.showStudio()
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        runtime.launch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return false
    }
}

private struct FloatingControlBarView: View {
    @Bindable var viewModel: AppViewModel
    let onOpenStudio: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(viewModel.isRecordingActive ? Color.red : Color.black)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.floatingControlTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.floatingControlSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Pick") {
                    DesktopRegionPicker.shared.begin(
                        on: viewModel.selectedDisplaySource,
                        onSelection: { rect in
                            viewModel.applyScreenSelection(rect)
                        }
                    )
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canAdjustCaptureSetup)
                .opacity(viewModel.canAdjustCaptureSetup ? 1 : 0.42)

                Button(viewModel.floatingPrimaryActionTitle) {
                    if viewModel.isRecordingActive {
                        Task {
                            await viewModel.stopRecordingSession()
                        }
                    } else {
                        viewModel.startRecordingSession()
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.92)))
                .foregroundStyle(.white)

                Button("Studio") {
                    onOpenStudio()
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canAdjustCaptureSetup)
                .opacity(viewModel.canAdjustCaptureSetup ? 1 : 0.42)

                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.borderless)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: RuntimeConstants.floatingPanelSize.width)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule().stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
    }
}

@main
struct CreatorRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
