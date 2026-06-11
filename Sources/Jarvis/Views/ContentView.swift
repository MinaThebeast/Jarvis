import SwiftUI

// MARK: - Root Content View

struct ContentView: View {
    @EnvironmentObject var vm: JarvisViewModel

    var body: some View {
        Group {
            if vm.isConfigured {
                HUDView()
                    .transition(.opacity)
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.6), value: vm.isConfigured)
        .ignoresSafeArea()
        .onDisappear {
            vm.stopJarvis()
        }
    }
}
