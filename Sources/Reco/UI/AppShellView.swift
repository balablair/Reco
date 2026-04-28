import SwiftUI
import RecoKit

struct AppShellView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.925, green: 0.925, blue: 0.937),
                    Color(red: 0.965, green: 0.969, blue: 0.976)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.white.opacity(0.42), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
                .blur(radius: 10)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // editing 阶段是纯编辑器，不需要 TopBar（标题 + 导航按钮）
                if viewModel.phase != .editing {
                    TopBarView(viewModel: viewModel)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }
                content
                    .padding(viewModel.phase == .editing ? 0 : 24)
                    .padding(.top, viewModel.phase == .editing ? 0 : 8)
            }

            if viewModel.phase == .editing && viewModel.exportSheetPresented {
                ExportSheetView(viewModel: viewModel)
                    .frame(width: 320)
                    .padding(.trailing, 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.exportSheetPresented)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .editing:
            EditorScreenView(viewModel: viewModel)
        default:
            Color.clear
        }
    }
}
