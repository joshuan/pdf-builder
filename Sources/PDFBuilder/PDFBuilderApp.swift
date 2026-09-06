import SwiftUI

@main
struct PDFBuilderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = BuilderModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 760, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Выбрать файлы…") {
                    model.chooseFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Button("Собрать PDF") {
                    model.createPDF()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.pages.isEmpty)
            }
        }
    }
}
