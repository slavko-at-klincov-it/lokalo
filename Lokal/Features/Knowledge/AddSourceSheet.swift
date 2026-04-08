//
//  AddSourceSheet.swift
//  Lokal
//
//  Sheet that lets the user add a new RAG source: local folder (Files app),
//  or any of the connected OAuth providers (GitHub repo / Drive / OneDrive).
//

import SwiftUI
import UniformTypeIdentifiers

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(KnowledgeBaseStore.self) private var kbStore
    @Environment(IndexingService.self) private var indexer
    @Environment(ConnectionStore.self) private var connections
    @Environment(EmbeddingModelStore.self) private var embedStore

    @State private var showFolderImporter = false
    @State private var showRepoBrowser = false
    @State private var showDriveBrowser = false
    @State private var showOneDriveBrowser = false

    var body: some View {
        NavigationStack {
            List {
                Section("Lokal") {
                    Button {
                        showFolderImporter = true
                    } label: {
                        Label("Ordner aus Files-App", systemImage: "folder")
                    }
                }
                Section("Cloud (verbinden via Verbindungen)") {
                    if connections.isConnected(.github) {
                        Button {
                            showRepoBrowser = true
                        } label: {
                            Label("GitHub Repo wählen", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    } else {
                        Label("GitHub nicht verbunden", systemImage: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    if connections.isConnected(.googleDrive) {
                        Button {
                            showDriveBrowser = true
                        } label: {
                            Label("Google Drive Ordner wählen", systemImage: "doc.circle")
                        }
                    } else {
                        Label("Google Drive nicht verbunden", systemImage: "doc.circle")
                            .foregroundStyle(.secondary)
                    }
                    if connections.isConnected(.onedrive) {
                        Button {
                            showOneDriveBrowser = true
                        } label: {
                            Label("OneDrive Ordner wählen", systemImage: "cloud")
                        }
                    } else {
                        Label("OneDrive nicht verbunden", systemImage: "cloud")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Quelle hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPicker(result)
            }
            .sheet(isPresented: $showRepoBrowser) {
                GitHubRepoBrowser { repo in
                    addRemoteSource(
                        kind: .githubRepo,
                        displayName: repo,
                        remoteRootID: repo
                    )
                }
            }
            .sheet(isPresented: $showDriveBrowser) {
                GoogleDriveBrowser { folderID, folderName in
                    addRemoteSource(
                        kind: .googleDriveFolder,
                        displayName: folderName,
                        remoteRootID: folderID
                    )
                }
            }
            .sheet(isPresented: $showOneDriveBrowser) {
                OneDriveBrowser { itemID, itemName in
                    addRemoteSource(
                        kind: .onedriveFolder,
                        displayName: itemName,
                        remoteRootID: itemID
                    )
                }
            }
        }
    }

    private func handleFolderPicker(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let source = KnowledgeSource(
                    kind: .localFolder,
                    displayName: url.lastPathComponent,
                    bookmark: bookmark
                )
                addToActiveBase(source)
            } catch {
                #if DEBUG
                print("bookmark error: \(error)")
                #endif
            }
        case .failure:
            break
        }
    }

    private func addRemoteSource(kind: KnowledgeSourceKind, displayName: String, remoteRootID: String) {
        let connection = connections.connection(for: kind == .githubRepo ? .github
                                                : kind == .googleDriveFolder ? .googleDrive
                                                : .onedrive)
        let source = KnowledgeSource(
            kind: kind,
            displayName: displayName,
            bookmark: nil,
            remoteRootID: remoteRootID,
            connectionID: connection?.id
        )
        addToActiveBase(source)
    }

    private func addToActiveBase(_ source: KnowledgeSource) {
        guard let entry = embedStore.activeEntry else { return }
        let kb = kbStore.createBaseIfNeeded(
            name: "Meine Wissensbasis",
            embeddingModelID: entry.id,
            dimensions: entry.dimensions
        )
        kbStore.add(source: source, toBase: kb.id)
        indexer.indexSource(source, in: kb.id)
        dismiss()
    }
}

// MARK: - GitHub repo browser

struct GitHubRepoBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionStore.self) private var connections
    @State private var repos: [GitHubOAuth.Repo] = []
    @State private var loading = true
    @State private var errorText: String?
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red).padding()
                } else {
                    List(repos, id: \.id) { repo in
                        Button {
                            onPick(repo.full_name)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(repo.full_name).font(.subheadline.weight(.medium))
                                Text(repo.private ? "privat" : "öffentlich")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Repository wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        do {
            let token = try await connections.freshAccessToken(for: .github)
            let list = try await GitHubOAuth.listRepos(token: token)
            repos = list
            loading = false
        } catch {
            errorText = error.lokaloMessage
            loading = false
        }
    }
}

// MARK: - Google Drive folder browser

struct GoogleDriveBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionStore.self) private var connections
    @State private var path: [GoogleDriveOAuth.DriveFile] = []
    @State private var children: [GoogleDriveOAuth.DriveFile] = []
    @State private var loading = true
    @State private var errorText: String?
    let onPick: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red).padding()
                } else {
                    List {
                        let folders = children.filter { $0.mimeType == "application/vnd.google-apps.folder" }
                        Section {
                            Button {
                                if let last = path.last {
                                    onPick(last.id, last.name)
                                } else {
                                    onPick("root", "Drive Root")
                                }
                                dismiss()
                            } label: {
                                Label("Diesen Ordner verwenden", systemImage: "checkmark.circle.fill")
                            }
                        }
                        Section("Unterordner") {
                            ForEach(folders, id: \.id) { folder in
                                Button {
                                    Task { await navigate(into: folder) }
                                } label: {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text(folder.name)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(path.last?.name ?? "Drive Root")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !path.isEmpty {
                        Button("Zurück") {
                            path.removeLast()
                            Task { await reload() }
                        }
                    }
                }
            }
            .task { await reload() }
        }
    }

    private func navigate(into folder: GoogleDriveOAuth.DriveFile) async {
        path.append(folder)
        await reload()
    }

    private func reload() async {
        loading = true
        do {
            let token = try await connections.freshAccessToken(for: .googleDrive)
            children = try await GoogleDriveOAuth.listFiles(token: token, parentID: path.last?.id)
            loading = false
        } catch {
            errorText = error.lokaloMessage
            loading = false
        }
    }
}

// MARK: - OneDrive folder browser

struct OneDriveBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionStore.self) private var connections
    @State private var path: [OneDriveOAuth.DriveItem] = []
    @State private var children: [OneDriveOAuth.DriveItem] = []
    @State private var loading = true
    @State private var errorText: String?
    let onPick: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red).padding()
                } else {
                    List {
                        Section {
                            Button {
                                if let last = path.last {
                                    onPick(last.id, last.name)
                                } else {
                                    onPick("root", "OneDrive Root")
                                }
                                dismiss()
                            } label: {
                                Label("Diesen Ordner verwenden", systemImage: "checkmark.circle.fill")
                            }
                        }
                        Section("Unterordner") {
                            ForEach(children.filter { $0.isFolder }, id: \.id) { folder in
                                Button {
                                    Task { await navigate(into: folder) }
                                } label: {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text(folder.name)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(path.last?.name ?? "OneDrive Root")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !path.isEmpty {
                        Button("Zurück") {
                            path.removeLast()
                            Task { await reload() }
                        }
                    }
                }
            }
            .task { await reload() }
        }
    }

    private func navigate(into folder: OneDriveOAuth.DriveItem) async {
        path.append(folder)
        await reload()
    }

    private func reload() async {
        loading = true
        do {
            let token = try await connections.freshAccessToken(for: .onedrive)
            children = try await OneDriveOAuth.listChildren(token: token, itemID: path.last?.id)
            loading = false
        } catch {
            errorText = error.lokaloMessage
            loading = false
        }
    }
}
