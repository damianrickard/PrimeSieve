import SwiftUI
import AppKit

@main
struct PrimeSieveApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1100, minHeight: 760)
                .task { await model.refresh() }
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1260, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Benchmark") {
                Button("Start Comparison") { model.run() }.keyboardShortcut("r").disabled(model.isRunning || model.isDiscovering)
                Button("Cancel Comparison") { model.cancel() }.keyboardShortcut(".").disabled(!model.isRunning)
                Button("Refresh Languages") { Task { await model.refresh() } }.disabled(model.isRunning || model.isDiscovering)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isRunning else { return .terminateNow }
        model.cancel()
        Task { @MainActor in
            while model.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
