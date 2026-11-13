import AppKit
import ScoutCore
import SwiftUI

/// ⌘L: type or paste a path. Tab completes folder names.
struct GoToPathView: View {
    let window: BrowserWindowModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Path").font(.headline)
            TextField("~/Documents or /usr/local", text: $path)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 460)
                .onKeyPress(.tab) {
                    if let completed = PathCompletion.complete(path, home: window.services.homePath) {
                        path = completed
                    }
                    return .handled
                }
                .onSubmit(go)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text("Tab completes folder names.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Go", action: go).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear {
            let current = window.current.location.filePath
            path = PathDisplay.display(current, home: window.services.homePath) + "/"
            if path.hasPrefix("iCloud") { path = current + "/" }
        }
    }

    private func go() {
        let expanded = PathCompletion.expandTilde(path.trimmingCharacters(in: .whitespaces), home: window.services.homePath)
        guard FileManager.default.fileExists(atPath: expanded) else {
            error = "Nothing exists at that path."
            return
        }
        window.current.reveal(URL(filePath: expanded))
        dismiss()
    }
}
