import AppKit
import Observation
import SwiftUI
import CreatorRecorderKit

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

@main
struct CreatorRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
