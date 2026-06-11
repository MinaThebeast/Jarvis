import SwiftUI

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = JarvisViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .background(Color.black)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(replacing: .appInfo) {
                Button("About JARVIS") {}
            }
        }
    }
}
