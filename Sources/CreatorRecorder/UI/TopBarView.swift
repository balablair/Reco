import SwiftUI
import CreatorRecorderKit

struct TopBarView: View {
    let viewModel: AppViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ModeSwitcherView(
                selectedPhase: viewModel.phase,
                recordingLocked: viewModel.isRecordingActive
            ) { phase in
                viewModel.transitionToPhase(phase)
            }

            HStack(spacing: 12) {
                if viewModel.phase == .editing {
                    Button("Export") {
                        viewModel.toggleExportSheet()
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                }

                Button(viewModel.phase == .recording ? "Stop Recording" : "Start Recording") {
                    if viewModel.phase == .recording {
                        Task {
                            await viewModel.stopRecordingSession()
                        }
                    } else {
                        viewModel.startRecordingSession()
                    }
                }
                .disabled(viewModel.phase != .recording && !viewModel.canAdjustCaptureSetup)
                .buttonStyle(PrimaryPillButtonStyle())
            }
        }
    }

    private var title: String {
        switch viewModel.phase {
        case .preparation: return "Studio Settings"
        case .recording: return "Recording On Desktop"
        case .completion: return "Recording Complete"
        case .editing: return "Platform Variants"
        }
    }

    private var subtitle: String {
        switch viewModel.phase {
        case .preparation: return "The floating control bar is now the main entry. Use this window for setup only."
        case .recording: return "Desktop-first recording with camera, teleprompter and a minimal HUD overlay."
        case .completion: return "Your recording is ready. Preview, redo, or open in Studio."
        case .editing: return "Use the floating pill to jump between Xiaohongshu, Douyin and Bilibili variants."
        }
    }
}
