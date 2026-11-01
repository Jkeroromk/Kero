//
//  SettingsView.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//

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
            ForEach(KeroCores.all) { core in
                Section(core.displayName) {
                    Text(Self.notice(for: core.id))
                        .font(.footnote)
                }
            }

            Section("Kero") {
                Text("Kero and Kero Engine © 2026 Zexin Zou. Kero doesn't include any games. Only play games you own.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Acknowledgements")
    }

    private static func notice(for coreID: String) -> String
    {
        switch coreID
        {
        case "kero.core.mgba":
            return """
            mGBA — Copyright © 2013–2025 Jeffrey Pfau and contributors. Used under the Mozilla Public License 2.0 (https://mozilla.org/MPL/2.0/). Source code: https://github.com/mgba-emu/mgba

            Includes inih — Copyright © 2009 Ben Hoyt, BSD 3-Clause License.
            """
        default:
            return ""
        }
    }
}
