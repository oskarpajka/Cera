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

    @State private var selectedProvider: APIProvider = .openAI
    @State private var apiKeyInput: String = ""
    @State private var keyVerificationState: KeyVerificationState = .idle
    @State private var hasStoredKey: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                translationModeSection
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
            .onAppear { refreshKeyStatus() }
        }
    }

    // MARK: - Languages

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
            Text("Offline translation packs are managed by iOS under Settings > General > Language & Region > Translation Languages.")
        }
    }

    // MARK: - Translation Mode

    @ViewBuilder
    private var translationModeSection: some View {
        Section {
            Picker("Mode", selection: modeBinding) {
                Text("Local (Offline)").tag("local")
                Text("Cloud API").tag("cloud")
            }

            if !viewModel.translationMode.isLocal {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(APIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: selectedProvider) {
                    viewModel.translationMode = .cloud(selectedProvider)
                    refreshKeyStatus()
                    apiKeyInput = ""
                    keyVerificationState = .idle
                }

                HStack {
                    SecureField("API Key", text: $apiKeyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    if !apiKeyInput.isEmpty {
                        Button("Save") { saveKey() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if hasStoredKey {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Key stored securely")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()

                        Button("Verify") { verifyKey() }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                        Button("Remove") { removeKey() }
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if keyVerificationState != .idle {
                    keyVerificationLabel
                }
            }
        } header: {
            Text("Translation Mode")
        } footer: {
            if viewModel.translationMode.isLocal {
                Text("All translation happens on-device. No data leaves your phone.")
            } else {
                Text("Text will be sent to \(selectedProvider.displayName) for translation. The app falls back to local mode automatically when offline.")
            }
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
            .disabled(!viewModel.isLLMAvailable || !viewModel.translationMode.isLocal)

            if !viewModel.isLLMAvailable {
                Label {
                    Text("Enable Apple Intelligence in Settings to use AI summaries.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            } else if !viewModel.translationMode.isLocal {
                Text("AI Summary is only available in local mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Processing")
        } footer: {
            Text("When enabled, Cera uses on-device AI to produce a natural summary and a scene description instead of a direct translation.")
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "2.0.0")
        }
    }

    // MARK: - Helpers

    private var modeBinding: Binding<String> {
        Binding(
            get: { viewModel.translationMode.isLocal ? "local" : "cloud" },
            set: { value in
                if value == "local" {
                    viewModel.translationMode = .local
                } else {
                    viewModel.translationMode = .cloud(selectedProvider)
                }
            }
        )
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        KeychainService.save(key: selectedProvider.keychainKey, value: key)
        apiKeyInput = ""
        refreshKeyStatus()
    }

    private func removeKey() {
        KeychainService.delete(key: selectedProvider.keychainKey)
        refreshKeyStatus()
        keyVerificationState = .idle
    }

    private func refreshKeyStatus() {
        hasStoredKey = selectedProvider.hasStoredKey

        if let provider = viewModel.translationMode.provider {
            selectedProvider = provider
        }
    }

    private func verifyKey() {
        keyVerificationState = .verifying
        Task {
            guard let key = KeychainService.load(key: selectedProvider.keychainKey) else {
                keyVerificationState = .failed
                return
            }
            let service = APITranslationService()
            let valid = await service.verifyKey(provider: selectedProvider, apiKey: key)
            keyVerificationState = valid ? .valid : .failed
        }
    }

    @ViewBuilder
    private var keyVerificationLabel: some View {
        switch keyVerificationState {
        case .idle:
            EmptyView()
        case .verifying:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Verifying key...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .valid:
            Label("Key is valid", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Key verification failed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Key Verification State

private enum KeyVerificationState {
    case idle
    case verifying
    case valid
    case failed
}
