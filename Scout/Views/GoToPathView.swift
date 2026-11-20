import AppKit
import ScoutCore
import SwiftUI

/// ⌘L: type or paste a path. Tab completes folder names. A command such as "code ." or
/// "terminal" opens the folder in that app instead.
struct GoToPathView: View {
    let window: BrowserWindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Path").font(.ui(13, .medium))
            TextField("~/Documents or /usr/local", text: $path)
                .textFieldStyle(.roundedBorder)
                .font(.ui(13).monospaced())
                .frame(width: 460)
                .onKeyPress(.tab) {
                    if let completed = PathCompletion.complete(path, home: window.services.homePath) {
                        path = completed
                    }
                    return .handled
                }
                .onSubmit(go)
            if let error {
                Text(error).font(.ui(12)).foregroundStyle(.red)
            } else {
                Text("Tab completes folder names. Type code . or terminal to open this folder in an app.").font(.ui(12)).foregroundStyle(Color.textSubtle)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go", action: go).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onWindowKey(.escape) {
            dismiss()
            return true
        }
        .onAppear {
            let current = window.current.location.filePath
            path = PathDisplay.display(current, home: window.services.homePath) + "/"
            if path.hasPrefix("iCloud") { path = current + "/" }
        }
    }

    private func go() {
        if let command = PathBarCommand.parse(path, known: DevApp.pathBarCommands) {
            run(command)
            return
        }
        let expanded = PathCompletion.expandTilde(path.trimmingCharacters(in: .whitespaces), home: window.services.homePath)
        guard FileManager.default.fileExists(atPath: expanded) else {
            error = "Nothing exists at that path."
            return
        }
        window.current.reveal(URL(filePath: expanded))
        dismiss()
    }

    /// "code .", "cursor app", "terminal ~/Sites", "finder".
    private func run(_ command: PathBarCommand) {
        let home = window.services.homePath
        let folder = command.target(current: window.current.location.filePath, home: home)
        guard FileManager.default.fileExists(atPath: folder) else {
            error = "Nothing exists at \(PathDisplay.display(folder, home: home))."
            return
        }
        let url = URL(filePath: folder)
        if command.name == "finder" {
            FinderBridge.reveal([url])
        } else if let app = DevApp.app(forCommand: command.name) {
            app.open(url)
        } else {
            error = "Scout didn’t find an app for “\(command.name)”."
            return
        }
        dismiss()
    }
}
