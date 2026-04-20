import SwiftUI
import CreatorRecorderKit

struct ModeSwitcherView: View {
    let selectedScreen: AppViewModel.Screen
    let recordingLocked: Bool
    let onSelect: (AppViewModel.Screen) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppViewModel.Screen.allCases) { screen in
                Button {
                    onSelect(screen)
                } label: {
                    Text(label(for: screen))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(screen == selectedScreen ? Color.black.opacity(0.84) : Color.black.opacity(0.54))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if screen == selectedScreen {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.82), Color.white.opacity(0.46)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(recordingLocked && screen != .recording)
                .opacity(recordingLocked && screen != .recording ? 0.42 : 1)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.05), radius: 14, y: 4)
    }

    private func label(for screen: AppViewModel.Screen) -> String {
        switch screen {
        case .preparation: return "Prepare"
        case .recording: return "Record"
        case .editor: return "Edit"
        }
    }
}


struct LargePreviewCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
                .background(Color.white.opacity(0.84))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 24, y: 6)
        }
    }
}

struct InspectorCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 20, y: 6)
    }
}

struct InspectorRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 13))
    }
}

struct TemplateRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(isActive ? Color.black : Color.clear)
                .stroke(Color.black.opacity(0.18), lineWidth: isActive ? 0 : 1)
                .frame(width: 16, height: 16)
        }
        .padding(12)
        .background(isActive ? Color.black.opacity(0.06) : Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct DisplayRow: View {
    let name: String
    let resolution: String
    let isPrimary: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                        if isPrimary {
                            Text("Primary")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                        }
                    }
                    Text(resolution)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(isSelected ? Color.black : Color.clear)
                    .stroke(Color.black.opacity(0.18), lineWidth: isSelected ? 0 : 1)
                    .frame(width: 16, height: 16)
            }
            .padding(12)
            .background(isSelected ? Color.black.opacity(0.06) : Color.black.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct QuickToggleCard: View {
    let title: String
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Capsule()
                .fill(active ? Color.black : Color.white)
                .overlay {
                    if !active {
                        Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1)
                    }
                }
                .frame(width: 42, height: 24)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 18, y: 6)
    }
}

struct GlassTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.68))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay {
                Capsule().stroke(Color.white.opacity(0.66), lineWidth: 1)
            }
            .clipShape(Capsule())
    }
}

struct PlatformPillView: View {
    let selectedPlatform: PlatformKind
    let onSelect: (PlatformKind) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(PlatformKind.allCases.enumerated()), id: \.element.id) { index, platform in
                Button {
                    onSelect(platform)
                } label: {
                    ZStack {
                        if platform == selectedPlatform {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.82), Color.white.opacity(0.42)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay {
                                    Capsule().stroke(Color.white.opacity(0.74), lineWidth: 1)
                                }
                        }

                        platformIcon(for: index)
                            .foregroundStyle(Color.black.opacity(platform == selectedPlatform ? 0.86 : 0.54))
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .help("\(platform.title) · \(platform.ratioLabel)")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule().stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
    }

    @ViewBuilder
    private func platformIcon(for index: Int) -> some View {
        switch index {
        case 0:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .frame(width: 11, height: 11)
        case 1:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .frame(width: 8, height: 14)
        default:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .frame(width: 14, height: 10)
        }
    }
}

struct TrimBarView: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Trim")
                Spacer()
                Text("00:00 - 00:45")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08)).frame(height: 36)
                Capsule().fill(Color.black).frame(width: 320, height: 28).padding(.leading, 120)
                Capsule().fill(Color.white).frame(width: 10, height: 32).padding(.leading, 120)
                Capsule().fill(Color.white).frame(width: 10, height: 32).padding(.leading, 430)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 18, y: 6)
    }
}

struct ExportSheetView: View {
    let viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Variants")
                .font(.system(size: 18, weight: .semibold))

            ForEach(viewModel.exportSelection.variants, id: \.id) { variant in
                Button {
                    viewModel.toggleExportVariant(variant.platform)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(variant.exportEnabled ? Color.black : Color.white)
                            .overlay {
                                if !variant.exportEnabled {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                                }
                            }
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(variant.platform.title)
                                .font(.system(size: 13, weight: .medium))
                            Text("\(variant.platform.ratioLabel) · \(Int(variant.platform.exportRenderSize.width))x\(Int(variant.platform.exportRenderSize.height))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(variant.exportEnabled ? Color.black.opacity(0.04) : Color.black.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if case let .completed(results) = viewModel.exportState {
                InspectorCard(title: "Exported") {
                    ForEach(results, id: \.platform) { result in
                        InspectorRow(
                            title: result.platform.title,
                            value: result.fileURL.lastPathComponent
                        )
                    }
                }
            } else if case let .failed(message) = viewModel.exportState {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }

            Spacer()

            InspectorCard(title: "Output") {
                InspectorRow(title: "Codec", value: "H.264")
                InspectorRow(title: "Resolution", value: primaryExportResolution)
                InspectorRow(title: "Folder", value: "Temp/CreatorRecorder/Exports")
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    viewModel.toggleExportSheet()
                }
                .buttonStyle(SecondaryPillButtonStyle())

                Button(exportButtonTitle) {
                    Task {
                        await viewModel.exportSelectedVariants()
                    }
                }
                .buttonStyle(PrimaryPillButtonStyle())
                .disabled(isExporting)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
    }

    private var primaryExportResolution: String {
        let first = viewModel.exportSelection.enabledVariants.first?.platform.exportRenderSize ?? viewModel.selectedPlatform.exportRenderSize
        return "\(Int(first.width))x\(Int(first.height))"
    }

    private var isExporting: Bool {
        if case .exporting = viewModel.exportState {
            return true
        }
        return false
    }

    private var exportButtonTitle: String {
        isExporting ? "Exporting..." : "Export"
    }
}
