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
                selectedScreen: viewModel.currentScreen,
                recordingLocked: viewModel.isRecordingActive
            ) { screen in
                viewModel.select(screen: screen)
            }

            HStack(spacing: 12) {
                if viewModel.currentScreen == .editor {
                    Button("Export") {
                        viewModel.toggleExportSheet()
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                }

                Button(viewModel.currentScreen == .recording ? "Stop Recording" : "Start Recording") {
                    if viewModel.currentScreen == .recording {
                        Task {
                            await viewModel.stopRecordingSession()
                        }
                    } else {
                        viewModel.startRecordingSession()
                    }
                }
                .disabled(viewModel.currentScreen != .recording && !viewModel.canAdjustCaptureSetup)
                .buttonStyle(PrimaryPillButtonStyle())
            }
        }
    }

    private var title: String {
        switch viewModel.currentScreen {
        case .preparation: return "Studio Settings"
        case .recording: return "Recording On Desktop"
        case .editor: return "Platform Variants"
        }
    }

    private var subtitle: String {
        switch viewModel.currentScreen {
        case .preparation: return "The floating control bar is now the main entry. Use this window for setup only."
        case .recording: return "Desktop-first recording with camera, teleprompter and a minimal HUD overlay."
        case .editor: return "Use the floating pill to jump between Xiaohongshu, Douyin and Bilibili variants."
        }
    }
}
