import AppKit
import SwiftUI

/// Shown once, on a new install: the three things worth knowing on day one.
struct WelcomeView: View {
    let done: () -> Void
    @State private var showInFinder = DefaultFileBrowser.isScout
    @State private var opensFolders = FolderHandler.isScout
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Scout").font(.ui(24, .medium)).foregroundStyle(Color.textStrong)
                    Text("The fastest way around your Mac.").font(.ui(14)).foregroundStyle(Color.textDefault)
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                step("command", "Jump from anywhere",
                     "Press ⌥Space in any app (or ⌘K in Scout) and type a few letters of a folder or file.")

                step("folder", "Make Scout your file browser",
                     note ?? "Folders and “Show in Finder” from other apps open here. Finder keeps the Desktop and Open/Save windows, and you can switch back any time in Settings.") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Open folders in Scout", isOn: Binding(get: { opensFolders }, set: { on in
                            Task {
                                do { try await FolderHandler.set(on); note = nil } catch {
                                    note = "macOS didn’t allow it: \(error.localizedDescription)"
                                }
                                opensFolders = FolderHandler.isScout
                            }
                        }))
                        Toggle("Use Scout for “Show in Finder”", isOn: Binding(get: { showInFinder }, set: { on in
                            DefaultFileBrowser.set(on)
                            showInFinder = DefaultFileBrowser.isScout
                        }))
                    }
                    .toggleStyle(.checkbox)
                    .font(.ui(13))
                    .foregroundStyle(Color.textDefault)
                }

                step("lock", "Let Scout see your folders",
                     "macOS asks before Scout can look in Downloads, Desktop and Documents: click Allow. Full Disk Access skips the questions.") {
                    Button("Open Privacy & Security") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    .controlSize(.small)
                }
            }

            HStack {
                Text("Developer? Turn on Developer tools in Settings for git and packages.")
                    .font(.ui(12))
                    .foregroundStyle(Color.textSubtle)
                Spacer()
                Button("Get Started", action: done)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 540)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String,
                      @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.textStrong)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSelected))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.ui(14, .medium)).foregroundStyle(Color.textStrong)
                Text(detail).font(.ui(13)).foregroundStyle(Color.textDefault)
                    .fixedSize(horizontal: false, vertical: true)
                extra().padding(.top, 4)
            }
        }
    }
}
