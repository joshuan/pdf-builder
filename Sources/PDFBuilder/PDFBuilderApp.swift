import SwiftUI

@main
struct PDFBuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = BuilderModel.shared

    var body: some Scene {
        Window("PDF Builder", id: "builder") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 760, height: 620)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await UpdateController.shared.checkNow() }
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Choose Files…") {
                    model.chooseFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Button("Build PDF") {
                    model.createPDF()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canCreatePDF)
            }
        }
    }
}
