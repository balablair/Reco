import AppKit
import SwiftUI
import CreatorRecorderKit

// MARK: - TeleprompterPanel

/// 录制时悬浮的提词器浮层
/// - 显示在屏幕底部，可拖动、可缩放字体大小
/// - 支持手动滚动与暂停
@MainActor
final class TeleprompterPanel: NSObject, NSWindowDelegate {
    static let shared = TeleprompterPanel()

    private var panel: NSPanel?
    private var viewModel: AppViewModel?

    private override init() {}

    func show(viewModel: AppViewModel) {
        self.viewModel = viewModel
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        createPanel(viewModel: viewModel)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    // MARK: - Private

    private func createPanel(viewModel: AppViewModel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelW: CGFloat = 680
        let panelH: CGFloat = 200
        let originX = (screenFrame.width - panelW) / 2 + screenFrame.minX
        let originY = screenFrame.minY + 40

        let rootView = TeleprompterView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.intrinsicContentSize]

        let newPanel = NSPanel(
            contentRect: CGRect(x: originX, y: originY, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isMovableByWindowBackground = true
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.contentView = hosting
        newPanel.delegate = self

        newPanel.orderFrontRegardless()
        self.panel = newPanel
    }
}

// MARK: - SwiftUI 提词器视图

struct TeleprompterView: View {
    @Bindable var viewModel: AppViewModel

    @State private var scrollOffset: CGFloat = 0
    @State private var textHeight: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?
    @State private var fontSize: CGFloat = 22
    @State private var isPaused = false

    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            scrollArea
        }
        .background(prompterBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 8)
        .frame(width: 680, height: 200)
        .onAppear { startScrolling() }
        .onDisappear {
            scrollTask?.cancel()
        }
        .onChange(of: viewModel.teleprompterText) { _, _ in
            restartScrolling()
        }
        .onChange(of: viewModel.teleprompterScrollSpeed) { _, _ in
            restartScrolling()
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                scrollTask?.cancel()
            } else {
                startScrolling()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    viewModel.teleprompterScrollSpeed = max(10, viewModel.teleprompterScrollSpeed - 10)
                    viewModel.savePreferences()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Text(String(format: "%.0f", viewModel.teleprompterScrollSpeed))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24)

                Button {
                    viewModel.teleprompterScrollSpeed = min(200, viewModel.teleprompterScrollSpeed + 10)
                    viewModel.savePreferences()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Button {
                    fontSize = max(14, fontSize - 2)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    fontSize = min(48, fontSize + 2)
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                scrollOffset = 0
                restartScrolling()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                isPaused.toggle()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var scrollArea: some View {
        GeometryReader { geo in
            let visibleH = geo.size.height
            ZStack {
                if viewModel.teleprompterText.isEmpty {
                    Text("在 PrepBar 提词器里输入你的台词…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(viewModel.teleprompterText)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineSpacing(8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { inner in
                                Color.clear.onAppear {
                                    textHeight = inner.size.height
                                }
                                .onChange(of: viewModel.teleprompterText) { _, _ in
                                    textHeight = inner.size.height
                                }
                                .onChange(of: fontSize) { _, _ in
                                    textHeight = inner.size.height
                                }
                            }
                        )
                        .offset(y: -scrollOffset + visibleH / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var prompterBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.72))
            )
    }

    private func startScrolling() {
        scrollTask?.cancel()
        guard !isPaused, !viewModel.teleprompterText.isEmpty else { return }
        let speed = max(1, viewModel.teleprompterScrollSpeed)
        scrollTask = Task {
            let interval: Double = 1.0 / 60.0
            let ptPerFrame = CGFloat(speed) * interval
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await MainActor.run {
                    let maxScroll = max(0, textHeight)
                    if scrollOffset >= maxScroll {
                        scrollOffset = 0
                    } else {
                        scrollOffset += ptPerFrame
                    }
                }
            }
        }
    }

    private func restartScrolling() {
        scrollTask?.cancel()
        scrollOffset = 0
        if isPaused { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startScrolling()
        }
    }
}

// MARK: - 提词器文本编辑浮层（点击 PrepBar 提词器图标时弹出）

struct TeleprompterEditSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("提词器")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
            }

            TextEditor(text: $viewModel.teleprompterText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(minHeight: 160)
                .onChange(of: viewModel.teleprompterText) { _, _ in
                    viewModel.savePreferences()
                }

            HStack {
                Text("滚动速度")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.teleprompterScrollSpeed, in: 10...200, step: 5)
                    .onChange(of: viewModel.teleprompterScrollSpeed) { _, _ in
                        viewModel.savePreferences()
                    }
                Text(String(format: "%.0f", viewModel.teleprompterScrollSpeed))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
