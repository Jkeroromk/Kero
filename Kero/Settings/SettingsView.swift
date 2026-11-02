//
//  SettingsView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

import SwiftData
import SwiftUI

import KeroEngine

struct SettingsView: View
{
    @Environment(\.dismiss) private var dismiss

    @AppStorage("videoFilter") private var filterRawValue = KeroVideoFilter.sharp.rawValue
    @AppStorage("integerScaling") private var usesIntegerScaling = false
    @AppStorage("alwaysShowTouchControls") private var alwaysShowTouchControls = false
    @AppStorage("landscapeLayout") private var landscapeLayout = "console"
    @AppStorage("foldedBehavior") private var foldedBehavior = "lid"
    @AppStorage("gameNameLanguage") private var gameNameLanguage = "auto"
    @AppStorage("downloadCovers") private var downloadCovers = true
    @Environment(\.modelContext) private var modelContext
    @AppStorage("lidColor") private var lidColor = KeroLidColor.graphite.rawValue

    var body: some View
    {
        NavigationStack {
            Form {
                Section {
                    Picker("Filter", selection: self.$filterRawValue) {
                        ForEach(KeroVideoFilter.allCases, id: \.rawValue) { filter in
                            Text(filter.name).tag(filter.rawValue)
                        }
                    }
                    Toggle("Integer Scaling", isOn: self.$usesIntegerScaling)
                } header: {
                    Text("Screen")
                } footer: {
                    Text("Integer scaling keeps every pixel the same size, with a slightly smaller picture.")
                }

                Section {
                    Picker("Landscape Layout", selection: self.$landscapeLayout) {
                        Text("Console").tag("console")
                        Text("Full Screen").tag("fullscreen")
                    }
                    Toggle("Always Show Touch Controls", isOn: self.$alwaysShowTouchControls)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Console keeps the controls beside the picture; Full Screen makes the picture bigger with controls on top of it. Touch controls hide automatically when a game controller is connected. Home button, or Menu + Options together, opens the pause menu. Hold the right trigger to fast-forward.")
                }

                Section {
                    Picker("When Folded", selection: self.$foldedBehavior) {
                        Text("Close the Lid").tag("lid")
                        Text("Keep Playing").tag("play")
                    }
                    if self.foldedBehavior == "lid"
                    {
                        Picker("Lid Colour", selection: self.$lidColor) {
                            ForEach(KeroLidColor.allCases) { color in
                                Text(color.name).tag(color.rawValue)
                            }
                        }
                    }
                } header: {
                    Text("iPhone Duo")
                } footer: {
                    Text("Folding your iPhone closes Kero like a clamshell: the game pauses and picks up where you left off when you open it again.")
                }

                Section {
                    Picker("Game Names", selection: self.$gameNameLanguage) {
                        Text("Automatic").tag("auto")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    Toggle("Download Covers", isOn: self.$downloadCovers)
                } header: {
                    Text("Library")
                } footer: {
                    Text("Kero recognises your games, including fan translations, and shows their official names. Covers come from the libretro thumbnail database; you can also choose your own from Photos by touching and holding a game.")
                }
                .onChange(of: self.gameNameLanguage) { _, _ in
                    KeroLibrary.updateNames(in: self.modelContext)
                }
                .onChange(of: self.downloadCovers) { _, enabled in
                    guard enabled, let games = try? self.modelContext.fetch(FetchDescriptor<KeroGame>()) else { return }
                    KeroCovers.fetchMissing(for: games, context: self.modelContext)
                }

                Section("Systems") {
                    ForEach(KeroCores.supportedSystems, id: \.self) { system in
                        LabeledContent(system.name, value: system.fileExtensions.map { "." + $0 }.joined(separator: " "))
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.dismiss() }
                }
            }
        }
    }
}

struct AcknowledgementsView: View
{
    var body: some View
    {
        List {
            ForEach(KeroCores.thirdPartyNotices) { notice in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(notice.usedFor)
                            .font(.footnote.weight(.semibold))
                        Text(notice.copyright)
                            .font(.footnote)
                        Text(notice.licenseText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Link(notice.url.absoluteString, destination: notice.url)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text([notice.name, notice.version].compactMap { $0 }.joined(separator: " ") + " · " + notice.license)
                }
            }

            Section("Game Information") {
                Text("Game names, regions and languages come from No-Intro data via libretro-database (https://github.com/libretro/libretro-database), used under Creative Commons Attribution-ShareAlike 4.0. Kero's game database files are shared under the same license. Covers are downloaded from the libretro thumbnail server; cover art belongs to its respective publishers.")
                    .font(.footnote)
            }

            Section("Kero") {
                Text("Kero and Kero Engine © 2026 Zexin Zou. Kero doesn't include any games. Only play games you own.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Acknowledgements")
    }

}
