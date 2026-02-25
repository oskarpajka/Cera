//
//  SettingsView.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                processingSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Default Languages

    @ViewBuilder
    private var languageSection: some View {
        Section {
            Picker("Source Language", selection: $viewModel.sourceLanguageCode) {
                Text("Auto-detect").tag("")
                ForEach(SupportedLanguage.all) { lang in
                    Text(lang.displayName).tag(lang.id)
                }
            }

            Picker("Target Language", selection: $viewModel.targetLanguageCode) {
                ForEach(SupportedLanguage.all) { lang in
                    Text(lang.displayName).tag(lang.id)
                }
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Manage Downloaded Languages", systemImage: "globe")
            }
        } header: {
            Text("Languages")
        } footer: {
            Text("Language preferences are saved to your device. Offline translation packs are managed by iOS under Settings → General → Language & Region → Translation Languages.")
        }
    }

    // MARK: - Processing

    @ViewBuilder
    private var processingSection: some View {
        Section {
            Toggle("AI Summary", isOn: Binding(
                get: { viewModel.enableSummary },
                set: { viewModel.enableSummary = $0 }
            ))
            .disabled(!viewModel.isLLMAvailable)

            if !viewModel.isLLMAvailable {
                Label {
                    Text("Enable Apple Intelligence in Settings → Apple Intelligence & Siri to use AI summaries.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Processing")
        } footer: {
            Text("When enabled, Cera uses on-device AI to produce a natural summary and a rich scene description. When disabled, you get a direct translation only.")
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
        }
    }
}
