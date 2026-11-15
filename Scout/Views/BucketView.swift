import AppKit
import ScoutCore
import SwiftUI

/// A cloud bucket (S3, Cloudflare R2…) as a page: folders and files, download, upload
/// (or drop files here, or F5 from the other pane), new folder and delete.
struct BucketView: View {
    let window: BrowserWindowModel
    let browser: BrowserModel
    let id: UUID
    @Environment(AppServices.self) private var services

    @State private var listing = BucketListing()
    @State private var isLoading = false
    @State private var error: String?
    @State private var selection: Set<String> = []
    @State private var confirmingDelete = false
    @State private var newFolderName: String?
    @State private var isDropTarget = false

    private var config: BucketConfig? { services.buckets.first { $0.id == id } }
    private var prefix: String { browser.bucketPrefix }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let isFolder: Bool
        let size: Int64?
        let modified: Date?
    }

    private var rows: [Row] {
        listing.folders.map { Row(id: $0, name: String($0.dropFirst(prefix.count).dropLast()), isFolder: true, size: nil, modified: nil) }
            + listing.objects.map { Row(id: $0.key, name: $0.name, isFolder: false, size: $0.size, modified: $0.modified) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.ui(12))
            }
            Table(rows, selection: $selection) {
                TableColumn("Name") { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.isFolder ? "folder.fill" : "doc").foregroundStyle(row.isFolder ? Color.accentColor : .secondary)
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                TableColumn("Modified") { row in
                    Text(row.modified?.formatted(date: .abbreviated, time: .shortened) ?? "").foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 150)
                TableColumn("Size") { row in
                    Text(row.size.map(Format.bytes) ?? "").foregroundStyle(.secondary).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                Button("Download") { download(keys) }
                Divider()
                Button("Delete…", role: .destructive) { selection = keys; confirmingDelete = true }
            } primaryAction: { keys in
                if keys.count == 1, let key = keys.first, key.hasSuffix("/") { browser.bucketPrefix = key } else { download(keys) }
            }
            .overlay {
                if !isLoading, rows.isEmpty, error == nil {
                    Text("Empty. Drop files here to upload them.").foregroundStyle(Color.textSubtle)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: isDropTarget ? 2 : 0))
            .dropDestination(for: URL.self) { urls, _ in
                services.upload(urls.filter(\.isFileURL), to: id, prefix: prefix)
                return true
            } isTargeted: { isDropTarget = $0 }
        }
        .padding(16)
        .task(id: "\(prefix)|\(services.bucketRevision)") { await load() }
        .alert("Delete \(selection.count) item\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { delete(selection) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They're removed from the bucket for good; there's no Trash in the cloud.")
        }
        .alert("New Folder", isPresented: Binding(get: { newFolderName != nil }, set: { if !$0 { newFolderName = nil } })) {
            TextField("Name", text: Binding(get: { newFolderName ?? "" }, set: { newFolderName = $0 }))
            Button("Create") { makeFolder() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { goUp() } label: { Image(systemName: "chevron.left") }
                .disabled(prefix.isEmpty).help("Up")
            Button(config?.bucket ?? "Bucket") { browser.bucketPrefix = "" }.buttonStyle(.plain).fontWeight(.medium)
            ForEach(crumbs, id: \.self) { crumb in
                Image(systemName: "chevron.compact.right").foregroundStyle(Color.textSubtle)
                Button(String(crumb.dropLast().split(separator: "/").last ?? "")) { browser.bucketPrefix = crumb }
                    .buttonStyle(.plain)
            }
            Spacer()
            if isLoading { ProgressView().controlSize(.small) }
            Button("New Folder") { newFolderName = "" }
            Button("Upload…") { chooseUpload() }
            Button("Download") { download(selection) }.disabled(selection.isEmpty)
        }
        .font(.ui(13))
    }

    private var crumbs: [String] {
        var result: [String] = []
        var path = ""
        for part in prefix.split(separator: "/") {
            path += part + "/"
            result.append(path)
        }
        return result
    }

    // MARK: - Work

    private func load() async {
        guard let client = services.client(for: id) else {
            error = "Scout can’t find this bucket’s secret key in your Keychain. Remove the bucket and add it again."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            listing = try await client.list(prefix: prefix)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        selection = []
    }

    private func goUp() {
        var parts = prefix.split(separator: "/")
        guard !parts.isEmpty else { return }
        parts.removeLast()
        browser.bucketPrefix = parts.isEmpty ? "" : parts.joined(separator: "/") + "/"
    }

    /// Where downloads go: the other pane's folder in split view, otherwise Downloads.
    private var downloadFolder: URL {
        if let other = window.otherPane?.current, other.isFolder { return other.location }
        return services.home.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    private func download(_ keys: Set<String>) {
        guard let client = services.client(for: id) else { return }
        let objects = listing.objects.filter { keys.contains($0.key) }
        guard !objects.isEmpty else { return }
        let folder = downloadFolder
        let transfer = Transfer(title: "Downloading \(objects.count == 1 ? "“\(objects[0].name)”" : "\(objects.count) files")",
                                totalBytes: objects.reduce(0) { $0 + $1.size })
        services.begin(transfer)
        Task {
            var done: Int64 = 0
            var errors: [String] = []
            for object in objects where !transfer.isCancelled {
                transfer.set(current: object.name)
                let target = LocalFileSource.availableURL(in: folder, preferredName: object.name, isDirectory: false, style: .numbered)
                do {
                    try await client.download(object.key, to: target)
                    done += object.size
                    transfer.set(done: done)
                } catch {
                    errors.append("\(object.name): \(error.localizedDescription)")
                }
            }
            services.end(transfer)
            if !errors.isEmpty { browser.alertMessage = errors.prefix(5).joined(separator: "\n") }
            for pane in window.panes where pane.current.isFolder { Task { await pane.current.reload() } }
        }
    }

    private func chooseUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        services.upload(panel.urls, to: id, prefix: prefix)
    }

    private func delete(_ keys: Set<String>) {
        guard let client = services.client(for: id) else { return }
        // Folders: only empty "folder/" markers are removed; their contents stay (no recursive deletes).
        Task {
            var errors: [String] = []
            for key in keys {
                do { try await client.delete(key) } catch { errors.append(error.localizedDescription) }
            }
            if !errors.isEmpty { browser.alertMessage = errors.prefix(5).joined(separator: "\n") }
            services.bucketChanged()
        }
    }

    private func makeFolder() {
        let name = (newFolderName ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        newFolderName = nil
        guard !name.isEmpty, let client = services.client(for: id) else { return }
        Task {
            do { try await client.makeFolder(prefix + name) } catch { browser.alertMessage = error.localizedDescription }
            services.bucketChanged()
        }
    }
}

/// Add Bucket: the connection details; the secret goes to the Keychain. Tests the
/// connection (a listing) before saving.
struct AddBucketView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    var onAdded: (UUID) -> Void

    @State private var name = ""
    @State private var endpoint = "https://"
    @State private var region = "auto"
    @State private var bucket = ""
    @State private var accessKey = ""
    @State private var secret = ""
    @State private var isTesting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Bucket").font(.ui(18, .medium))
            Text("Any S3-compatible storage: Cloudflare R2, Amazon S3, Backblaze B2, MinIO. The secret key is kept in your Keychain.")
                .font(.ui(12)).foregroundStyle(Color.textSubtle)
            Form {
                TextField("Name", text: $name, prompt: Text("Phreno assets"))
                TextField("Endpoint", text: $endpoint, prompt: Text("https://<account>.r2.cloudflarestorage.com"))
                TextField("Region", text: $region, prompt: Text("auto (R2) or us-east-1"))
                TextField("Bucket", text: $bucket)
                TextField("Access key ID", text: $accessKey)
                SecureField("Secret access key", text: $secret)
            }
            if let error { Text(error).font(.ui(12)).foregroundStyle(.red) }
            HStack {
                Spacer()
                if isTesting { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(bucket.isEmpty || accessKey.isEmpty || secret.isEmpty || !endpoint.hasPrefix("https://") || isTesting)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func connect() {
        let config = BucketConfig(name: name.isEmpty ? bucket : name, endpoint: endpoint.trimmingCharacters(in: .whitespaces),
                                  region: region.isEmpty ? "auto" : region, bucket: bucket.trimmingCharacters(in: .whitespaces),
                                  accessKeyID: accessKey.trimmingCharacters(in: .whitespaces))
        isTesting = true
        error = nil
        Task {
            defer { isTesting = false }
            do {
                _ = try await S3Client(config: config, secretKey: secret).list(prefix: "")
                services.saveBucket(config, secret: secret)
                onAdded(config.id)
                dismiss()
            } catch {
                self.error = "Couldn’t connect: \(error.localizedDescription)"
            }
        }
    }
}
