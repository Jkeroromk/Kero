//
//  KeroAddGamesView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Every way to get games into Kero: files, folders, Wi-Fi Transfer, AirDrop and the homebrew catalog.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KeroAddGamesView: View
{
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    /// Non-nil while the file picker is showing.
    @State private var importerTypes: [UTType]?
    @State private var status: String?

    var body: some View
    {
        NavigationStack {
            List {
                Section {
                    Button {
                        self.importerTypes = [.item]
                    } label: {
                        KeroAddGamesRow(title: "Files", subtitle: "Choose .nds, .gba, .gbc, .gb or .zip files", symbol: "doc.fill")
                    }

                    Button {
                        self.importerTypes = [.folder]
                    } label: {
                        KeroAddGamesRow(title: "Folder", subtitle: "Import every game in a folder at once", symbol: "folder.fill")
                    }

                    NavigationLink {
                        KeroWiFiTransferView()
                    } label: {
                        KeroAddGamesRow(title: "Wi-Fi Transfer", subtitle: "Send games from a computer's browser", symbol: "wifi")
                    }

                    if !KeroHomebrewCatalog.games.isEmpty
                    {
                        NavigationLink {
                            KeroHomebrewStoreView()
                        } label: {
                            KeroAddGamesRow(title: "Free Homebrew", subtitle: "New games their authors share for free", symbol: "sparkles")
                        }
                    }
                } footer: {
                    Text("AirDrop works too: send a game or a zip to this iPhone and choose Kero. Only import games you own.")
                }

                if self.appModel.importsInProgress > 0
                {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Importing…")
                        }
                    }
                }
                else if let status = self.status
                {
                    Section {
                        Text(status)
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
            .navigationTitle("Add Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.dismiss() }
                }
            }
            .fileImporter(isPresented: Binding(get: { self.importerTypes != nil }, set: { if !$0 { self.importerTypes = nil } }),
                          allowedContentTypes: self.importerTypes ?? [.item],
                          allowsMultipleSelection: true) { result in
                switch result
                {
                case .success(let urls):
                    Task {
                        let result = await self.appModel.importFiles(urls)
                        self.status = Self.describe(result)
                    }

                case .failure(let error):
                    self.status = error.localizedDescription
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    static func describe(_ result: KeroLibrary.ImportResult) -> String
    {
        var parts: [String] = []
        switch result.imported.count
        {
        case 0: break
        case 1: parts.append("Added \(result.imported[0].name).")
        default: parts.append("Added \(result.imported.count) games.")
        }

        if let summary = result.summary
        {
            parts.append(summary.text)
        }

        return parts.isEmpty ? "No games found." : parts.joined(separator: "\n")
    }
}

struct KeroAddGamesRow: View
{
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View
    {
        HStack(spacing: 14) {
            Image(systemName: self.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.body.weight(.semibold))
                Text(self.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Wi-Fi Transfer -

struct KeroWiFiTransferView: View
{
    @Environment(AppModel.self) private var appModel

    @State private var server = KeroTransferServer()
    @State private var state: KeroTransferServer.State = .stopped
    @State private var address = KeroTransferServer.localAddress()
    @State private var received: [Received] = []

    struct Received: Identifiable
    {
        let id = UUID()
        var name: String
        var status: String
        var succeeded: Bool?
    }

    private var url: String? {
        guard case .running(let port) = self.state, let address = self.address else { return nil }
        return port == 80 ? "http://\(address)" : "http://\(address):\(port)"
    }

    var body: some View
    {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    switch self.state
                    {
                    case .running where self.url != nil:
                        Text("On a computer connected to the same Wi-Fi, open:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(self.url ?? "")
                            .font(.system(size: 26, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("Drop games on the page and they'll appear here. Keep this screen open while sending.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                    case .running:
                        Label("Connect this iPhone to Wi-Fi to use Wi-Fi Transfer.", systemImage: "wifi.exclamationmark")

                    case .failed(let reason):
                        Label("Wi-Fi Transfer couldn't start: \(reason)", systemImage: "exclamationmark.triangle")

                    case .stopped, .starting:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Starting…")
                        }
                    }
                }
                .padding(.vertical, 6)

                if let url = self.url
                {
                    Button {
                        UIPasteboard.general.string = url
                    } label: {
                        Label("Copy Address", systemImage: "doc.on.doc")
                    }
                }
            }

            if !self.received.isEmpty
            {
                Section("Received") {
                    ForEach(self.received.reversed()) { item in
                        HStack(spacing: 10) {
                            Group {
                                switch item.succeeded
                                {
                                case .none: ProgressView()
                                case .some(true): Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                case .some(false): Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                                }
                            }
                            .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .lineLimit(1)
                                Text(item.status)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Wi-Fi Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            self.server.onStateChange = { state in
                self.state = state
                self.address = KeroTransferServer.localAddress()
            }
            self.server.onFileReceived = { url, name in
                self.receive(url, name: name)
            }
            self.server.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            self.server.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func receive(_ url: URL, name: String)
    {
        let item = Received(name: name, status: "Importing…", succeeded: nil)
        self.received.append(item)

        Task {
            let result = await self.appModel.importFiles([url])
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())

            guard let index = self.received.firstIndex(where: { $0.id == item.id }) else { return }

            if !result.imported.isEmpty
            {
                let names = result.imported.map(\.name).joined(separator: ", ")
                self.received[index].status = "Added " + names
                self.received[index].succeeded = true
            }
            else if !result.duplicates.isEmpty
            {
                self.received[index].status = "Already in your library"
                self.received[index].succeeded = true
            }
            else
            {
                self.received[index].status = result.failures.first?.reason ?? "Not a game Kero can open"
                self.received[index].succeeded = false
            }
        }
    }
}
