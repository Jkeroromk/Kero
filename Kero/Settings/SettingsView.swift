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
                    Toggle("Always Show Touch Controls", isOn: self.$alwaysShowTouchControls)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Touch controls hide automatically when a game controller is connected. Home button, or Menu + Options together, opens the pause menu. Hold the right trigger to fast-forward.")
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

            Includes blip_buf — Copyright © 2003–2009 Shay Green, GNU Lesser General Public License 2.1. Includes inih — Copyright © 2009 Ben Hoyt, BSD 3-Clause License.
            """
        default:
            return ""
        }
    }
}
