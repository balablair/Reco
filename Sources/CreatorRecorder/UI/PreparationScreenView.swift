import SwiftUI
import CreatorRecorderKit

struct PreparationScreenView: View {
    let viewModel: AppViewModel

    @State private var dragStartPoint: CGPoint?
    @State private var draftRegion: CaptureRegion?
    @State private var cameraDragOffset: CGSize = .zero
    @State private var cameraDragStartOrigin: CGPoint?
    @State private var cameraResizeTranslation: CGSize = .zero
    @State private var cameraResizeStartLayout: CameraOverlayLayout?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.86, green: 0.91, blue: 0.99), Color(red: 0.97, green: 0.96, blue: 0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 2)
                .padding(54)
                .shadow(color: .black.opacity(0.16), radius: 46)

            VStack {
                HStack {
                    GlassTag(text: viewModel.regionSelectionActive ? "Drag To Pick Region" : "Prepare On Desktop")
                    Spacer()
                    Text(statusCopy)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 54)
                .padding(.top, 34)

                Spacer()
            }

            VStack {
                TeleprompterPlaceholder()
                    .opacity(viewModel.overlayState.teleprompterVisible ? 1 : 0.22)
                    .padding(.horizontal, 92)
                    .padding(.top, 78)
                Spacer()
            }

            desktopStage

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(spacing: 10) {
                        Button {
                            viewModel.toggleCameraOverlay()
                        } label: {
                            QuickToggleCard(title: "Camera", active: viewModel.overlayState.cameraVisible)
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.toggleTeleprompterOverlay()
                        } label: {
                            QuickToggleCard(title: "Teleprompter", active: viewModel.overlayState.teleprompterVisible)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 190)

                    VStack(spacing: 10) {
                        Button {
                            viewModel.toggleMicrophone()
                        } label: {
                            QuickToggleCard(title: "Mic", active: viewModel.overlayState.microphoneEnabled)
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.toggleSystemAudio()
                        } label: {
                            QuickToggleCard(title: "System", active: viewModel.overlayState.systemAudioEnabled)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 190)

                    Spacer()

                    VStack(spacing: 12) {
                        InspectorCard(title: "Display") {
                            ForEach(viewModel.availableDisplays) { display in
                                DisplayRow(
                                    name: display.name,
                                    resolution: "\(Int(display.frame.width)) × \(Int(display.frame.height))",
                                    isPrimary: display.isPrimary,
                                    isSelected: display.id == viewModel.selectedDisplayID
                                ) {
                                    viewModel.select(displayID: display.id)
                                }
                            }
                        }

                        InspectorCard(title: "Template") {
                            ForEach(ProjectTemplate.allCases) { template in
                                TemplateRow(title: template.platform.title, subtitle: template.platform.ratioLabel, isActive: template == .xiaohongshu)
                            }
                        }

                        InspectorCard(title: "Region") {
                            InspectorRow(title: "Origin", value: "\(Int(activeRegion.origin.x)), \(Int(activeRegion.origin.y))")
                            InspectorRow(title: "Size", value: "\(Int(activeRegion.size.width)) × \(Int(activeRegion.size.height))")
                            InspectorRow(title: "Mode", value: viewModel.regionSelectionActive ? "Picking" : "Locked")
                        }

                        InspectorCard(title: "Camera") {
                            CameraShapePicker(selectedShape: activeCameraOverlay.style.shape) { shape in
                                viewModel.updateCameraShape(shape)
                            }
                            InspectorRow(title: "Position", value: "\(Int(activeCameraOverlay.origin.x)), \(Int(activeCameraOverlay.origin.y))")
                            InspectorRow(title: "Frame", value: "\(Int(activeCameraOverlay.size.width)) × \(Int(activeCameraOverlay.size.height))")
                            InspectorRow(title: "Resize", value: "Drag corner handle")
                            Button("Reset Camera Position") {
                                cameraDragOffset = .zero
                                cameraDragStartOrigin = nil
                                cameraResizeTranslation = .zero
                                cameraResizeStartLayout = nil
                                viewModel.resetCameraOverlay()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.58))
                        }

                        HStack(spacing: 10) {
                            Button(viewModel.regionSelectionActive ? "Cancel Picking" : "Pick Region") {
                                cancelOrTogglePicking()
                            }
                            .buttonStyle(SecondaryPillButtonStyle())

                            Button("Stage Recording") {
                                viewModel.startRecordingSession()
                            }
                            .buttonStyle(PrimaryPillButtonStyle())
                        }
                    }
                    .frame(width: 340)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadAvailableDisplays()
        }
    }

    private func loadAvailableDisplays() async {
        await viewModel.bootstrap()
    }

    private var activeRegion: CaptureRegion {
        draftRegion ?? viewModel.captureRegion
    }

    private var activeCameraOverlay: CameraOverlayLayout {
        viewModel.cameraOverlay.clamped(to: activeRegion)
    }

    private var statusCopy: String {
        if viewModel.regionSelectionActive {
            return "Drag anywhere on the desktop stage to define the recording bounds."
        }
        return "Region, camera and teleprompter are staged directly over the desktop."
    }

    private var desktopStage: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let region = activeRegion.clamped(to: canvasSize)
            let overlay = activeCameraOverlay.clamped(to: region)

            ZStack(alignment: .topLeading) {
                desktopTexture

                if viewModel.overlayState.hudVisible {
                    stageHUD
                        .padding(18)
                }

                if viewModel.overlayState.cameraVisible {
                    CameraOverlayView(layout: overlay)
                        .gesture(cameraDragGesture(in: region))
                        .simultaneousGesture(cameraResizeGesture(in: region))
                }

                RegionMask(region: region)

                CaptureRegionOutline(region: region, isPicking: viewModel.regionSelectionActive)

                regionBadge(region: region)
                    .position(x: region.origin.x + 92, y: max(region.origin.y - 16, 24))
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .task(id: proxy.size) {
                viewModel.updateCaptureCanvasSize(proxy.size)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1.4)
            }
            .shadow(color: .black.opacity(0.08), radius: 30, y: 14)
            .padding(.horizontal, 190)
            .padding(.vertical, 130)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .gesture(regionSelectionGesture(in: canvasSize))
        }
    }

    private var desktopTexture: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.93, blue: 0.89), Color(red: 0.90, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.52))
                        .frame(width: 220, height: 126)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.38))
                        .frame(maxWidth: .infinity, maxHeight: 126)
                }
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.32))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.48))
                        .frame(width: 260)
                }
            }
            .padding(26)
        }
    }

    private var stageHUD: some View {
        HStack(spacing: 10) {
            GlassTag(text: "Desktop Preview")
            Text("Camera and teleprompter float on top of the capture frame.")
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.56))
        }
    }

    private func regionBadge(region: CaptureRegion) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.regionSelectionActive ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text("\(Int(region.size.width)) × \(Int(region.size.height))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .clipShape(Capsule())
    }

    private func regionSelectionGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard viewModel.regionSelectionActive else { return }
                if dragStartPoint == nil {
                    dragStartPoint = clamped(value.startLocation, in: canvasSize)
                }
                guard let dragStartPoint else { return }
                let currentPoint = clamped(value.location, in: canvasSize)
                let region = CaptureRegion(from: dragStartPoint, to: currentPoint).clamped(to: canvasSize)
                draftRegion = region
            }
            .onEnded { value in
                guard viewModel.regionSelectionActive else { return }
                let start = dragStartPoint ?? clamped(value.startLocation, in: canvasSize)
                let end = clamped(value.location, in: canvasSize)
                let region = (draftRegion ?? CaptureRegion(from: start, to: end)).clamped(to: canvasSize)
                viewModel.updateCaptureRegion(region, canvasSize: canvasSize)
                draftRegion = nil
                dragStartPoint = nil
                cameraDragOffset = .zero
                cameraDragStartOrigin = nil
                cameraResizeTranslation = .zero
                cameraResizeStartLayout = nil
                viewModel.setRegionSelection(active: false)
            }
    }

    private func cameraDragGesture(in region: CaptureRegion) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard !viewModel.regionSelectionActive else { return }
                guard !cameraResizeHandleFrame(for: activeCameraOverlay).contains(value.startLocation) else { return }
                if cameraDragStartOrigin == nil {
                    cameraDragStartOrigin = activeCameraOverlay.origin
                }
                guard let cameraDragStartOrigin else { return }
                cameraDragOffset = value.translation
                let overlay = CameraOverlayLayout(
                    origin: CGPoint(
                        x: cameraDragStartOrigin.x + cameraDragOffset.width,
                        y: cameraDragStartOrigin.y + cameraDragOffset.height
                    ),
                    size: activeCameraOverlay.size,
                    style: activeCameraOverlay.style
                )
                viewModel.updateCameraOverlay(overlay.clamped(to: region))
            }
            .onEnded { _ in
                cameraDragOffset = .zero
                cameraDragStartOrigin = nil
            }
    }

    private func cameraResizeGesture(in region: CaptureRegion) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard !viewModel.regionSelectionActive else { return }
                let handleFrame = cameraResizeHandleFrame(for: activeCameraOverlay)
                guard handleFrame.contains(value.startLocation) else { return }
                if cameraResizeStartLayout == nil {
                    cameraResizeStartLayout = activeCameraOverlay
                }
                guard let cameraResizeStartLayout else { return }
                cameraResizeTranslation = value.translation
                viewModel.updateCameraOverlay(cameraResizeStartLayout.resized(by: cameraResizeTranslation, in: region))
            }
            .onEnded { _ in
                cameraResizeTranslation = .zero
                cameraResizeStartLayout = nil
            }
    }

    private func cameraResizeHandleFrame(for layout: CameraOverlayLayout) -> CGRect {
        CGRect(
            x: layout.origin.x + layout.size.width - 24,
            y: layout.origin.y + layout.size.height - 24,
            width: 32,
            height: 32
        )
    }

    private func clamped(_ point: CGPoint, in canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    private func cancelOrTogglePicking() {
        draftRegion = nil
        dragStartPoint = nil
        cameraDragOffset = .zero
        cameraDragStartOrigin = nil
        cameraResizeTranslation = .zero
        cameraResizeStartLayout = nil
        if viewModel.regionSelectionActive {
            viewModel.setRegionSelection(active: false)
        } else {
            beginDesktopRegionSelection()
        }
    }

    private func beginDesktopRegionSelection() {
        let display = viewModel.selectedDisplaySource
        viewModel.setRegionSelection(active: true)
        DesktopRegionPicker.shared.begin(
            on: display,
            onSelection: { selectionRect in
                let configuration = CaptureSessionConfiguration.fromScreenSelection(
                    selectionRect,
                    on: display,
                    cameraOverlay: viewModel.overlayState.cameraVisible ? viewModel.cameraOverlay : nil,
                    microphoneEnabled: viewModel.overlayState.microphoneEnabled,
                    systemAudioEnabled: viewModel.overlayState.systemAudioEnabled
                )
                viewModel.updateCaptureCanvasSize(configuration.canvasSize)
                viewModel.updateCaptureRegion(configuration.region, canvasSize: configuration.canvasSize)
                viewModel.setRegionSelection(active: false)
            },
            onCancel: {
                viewModel.setRegionSelection(active: false)
            }
        )
    }
}

struct DesktopRegionPickerOverlay: View {
    let displayFrame: CGRect
    let cancelsOnEscape: Bool
    let onCommit: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var dragStartPoint: CGPoint?
    @State private var draftRegion: CaptureRegion?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.22))
                    .ignoresSafeArea()

                if let draftRegion {
                    Canvas { context, size in
                        let outerRect = CGRect(origin: .zero, size: size)
                        var path = Path()
                        path.addRect(outerRect)
                        path.addRoundedRect(in: draftRegion.rect, cornerSize: .init(width: 28, height: 28))
                        context.fill(path, with: .color(Color.black.opacity(0.36)), style: FillStyle(eoFill: true))
                    }
                    CaptureRegionOutline(region: draftRegion, isPicking: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Drag to Pick Region")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Release to confirm, press Esc to cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(20)
                .background(Color.black.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(24)
            }
            .contentShape(Rectangle())
            .gesture(selectionGesture(in: proxy.size))
            .focusable(cancelsOnEscape)
            .onExitCommand {
                guard cancelsOnEscape else { return }
                onCancel()
            }
        }
    }

    private func selectionGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragStartPoint == nil {
                    dragStartPoint = clamped(value.startLocation, in: canvasSize)
                }
                guard let dragStartPoint else { return }
                let currentPoint = clamped(value.location, in: canvasSize)
                draftRegion = CaptureRegion(from: dragStartPoint, to: currentPoint).clamped(to: canvasSize)
            }
            .onEnded { value in
                let start = dragStartPoint ?? clamped(value.startLocation, in: canvasSize)
                let end = clamped(value.location, in: canvasSize)
                let region = (draftRegion ?? CaptureRegion(from: start, to: end)).clamped(to: canvasSize)
                dragStartPoint = nil
                draftRegion = nil
                let screenRect = CGRect(
                    x: displayFrame.minX + region.origin.x,
                    y: displayFrame.minY + region.origin.y,
                    width: region.size.width,
                    height: region.size.height
                ).integral
                onCommit(screenRect)
            }
    }

    private func clamped(_ point: CGPoint, in canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }
}

private struct TeleprompterPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.35))
            .frame(height: 70)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Color.white.opacity(0.24)).frame(width: 320, height: 10)
                    Capsule().fill(Color.white.opacity(0.16)).frame(width: 224, height: 10)
                }
                .padding(.horizontal, 18)
            }
    }
}

private struct RegionMask: View {
    let region: CaptureRegion

    var body: some View {
        Canvas { context, size in
            let outerRect = CGRect(origin: .zero, size: size)
            let innerRect = region.rect
            var path = Path()
            path.addRect(outerRect)
            path.addRoundedRect(in: innerRect, cornerSize: .init(width: 28, height: 28))
            context.fill(path, with: .color(Color.black.opacity(0.22)), style: FillStyle(eoFill: true))
        }
    }
}

private struct CaptureRegionOutline: View {
    let region: CaptureRegion
    let isPicking: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            .foregroundStyle(isPicking ? Color.orange.opacity(0.95) : Color.white.opacity(0.92))
            .frame(width: region.size.width, height: region.size.height)
            .position(x: region.origin.x + region.size.width / 2, y: region.origin.y + region.size.height / 2)
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }
}

private struct CameraOverlayView: View {
    let layout: CameraOverlayLayout

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                shapeFill
                shapeStroke
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.36))
                        .frame(width: 26, height: 26)
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 52, height: 10)
                }
            }

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .padding(8)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .position(
            x: layout.origin.x + layout.size.width / 2,
            y: layout.origin.y + layout.size.height / 2
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .help("Drag to move camera overlay")
    }

    @ViewBuilder
    private var shapeFill: some View {
        switch layout.style.shape {
        case .circle:
            Circle().fill(.ultraThinMaterial)
        case .roundedCard:
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.ultraThinMaterial)
        case .square:
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var shapeStroke: some View {
        switch layout.style.shape {
        case .circle:
            Circle().stroke(Color.white.opacity(0.74), lineWidth: 1)
        case .roundedCard:
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.74), lineWidth: 1)
        case .square:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.74), lineWidth: 1)
        }
    }
}

private struct CameraShapePicker: View {
    let selectedShape: CameraShape
    let onSelect: (CameraShape) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CameraShape.allCases, id: \.self) { shape in
                Button {
                    onSelect(shape)
                } label: {
                    ZStack {
                        if shape == selectedShape {
                            Capsule()
                                .fill(Color.black.opacity(0.08))
                        }
                        icon(for: shape)
                            .foregroundStyle(Color.black.opacity(shape == selectedShape ? 0.82 : 0.5))
                    }
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.03))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func icon(for shape: CameraShape) -> some View {
        switch shape {
        case .circle:
            Circle()
                .frame(width: 14, height: 14)
        case .roundedCard:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .frame(width: 18, height: 14)
        case .square:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .frame(width: 14, height: 14)
        }
    }
}
