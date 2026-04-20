import SwiftUI
import CreatorRecorderKit

struct AppShellView: View {
    @State var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .trailing) {
            Color(red: 0.965, green: 0.957, blue: 0.941)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                TopBarView(viewModel: viewModel)
                content
                if viewModel.currentScreen == .editor {
                    TrimBarView()
                }
            }
            .padding(24)

            if viewModel.currentScreen == .editor && viewModel.exportSheetPresented {
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
        switch viewModel.currentScreen {
        case .preparation:
            PreparationScreenView(viewModel: viewModel)
        case .recording:
            RecordingScreenView(viewModel: viewModel)
        case .editor:
            EditorScreenView(viewModel: viewModel)
        }
    }
}
