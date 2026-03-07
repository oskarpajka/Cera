//
//  ContentView.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import SwiftUI
import AVFoundation
import Translation

// MARK: - Content View

struct ContentView: View {
    @State private var viewModel = CameraViewModel()
    @State private var showSettings = false
    @State private var showSourcePicker = false
    @State private var showTargetPicker = false
    @State private var sheetVisible = false
    @State private var showOfflineToast = false
    @State private var translationConfig = TranslationSession.Configuration(
        source: nil,
        target: Locale.Language(identifier: "en")
    )

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.cameraService.session)
                .ignoresSafeArea()

            controlsLayer

            // Capture flash -- white overlay that fades out.
            Color.white
                .opacity(viewModel.showCaptureFlash ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if sheetVisible {
                TranslationSheetView(
                    summaryText: viewModel.summaryText,
                    fallbackTranslation: viewModel.fallbackTranslation,
                    originalText: viewModel.originalText,
                    sceneDescription: viewModel.sceneDescription,
                    state: viewModel.state,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            sheetVisible = false
                        }
                        viewModel.clearResults()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Offline fallback toast
            if showOfflineToast {
                offlineToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if viewModel.cameraPermission == .denied {
                permissionDeniedView
            }
        }
        .ignoresSafeArea()
        .task { await viewModel.setup() }
        .translationTask(translationConfig) { session in
            viewModel.bindTranslationSession(session)
        }
        .onChange(of: viewModel.sourceLanguageCode) { updateTranslationConfig() }
        .onChange(of: viewModel.targetLanguageCode) { updateTranslationConfig() }
        .onChange(of: viewModel.hasResults) { _, hasResults in
            if hasResults && !sheetVisible {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    sheetVisible = true
                }
            }
        }
        .onChange(of: viewModel.didFallbackOffline) { _, offline in
            if offline {
                withAnimation { showOfflineToast = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showOfflineToast = false }
                }
            }
        }
        .onDisappear { viewModel.tearDown() }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSourcePicker) {
            languagePickerSheet(
                title: "Source Language",
                selection: $viewModel.sourceLanguageCode,
                showAutoDetect: true
            )
        }
        .sheet(isPresented: $showTargetPicker) {
            languagePickerSheet(
                title: "Target Language",
                selection: $viewModel.targetLanguageCode,
                showAutoDetect: false
            )
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsLayer: some View {
        VStack {
            topBar
            Spacer()
            if !sheetVisible {
                bottomControls
            }
        }
        .padding(.top, 60)
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            statusBadge
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gear")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Bottom Controls (Language Bar + Capture Button)

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Language bar
            languageBar

            // Capture button
            captureButton
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var languageBar: some View {
        HStack(spacing: 0) {
            Button { showSourcePicker = true } label: {
                Text(viewModel.languageDisplayName(for: viewModel.sourceLanguageCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            Button {
                guard !viewModel.sourceLanguageCode.isEmpty else { return }
                let temp = viewModel.sourceLanguageCode
                viewModel.sourceLanguageCode = viewModel.targetLanguageCode
                viewModel.targetLanguageCode = temp
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
            }

            Button { showTargetPicker = true } label: {
                Text(viewModel.languageDisplayName(for: viewModel.targetLanguageCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var captureButton: some View {
        Button {
            viewModel.capture()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 60, height: 60)

                if viewModel.isCapturing {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.black)
                }
            }
        }
        .disabled(viewModel.isCapturing)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            if !viewModel.translationMode.isLocal, let provider = viewModel.translationMode.provider {
                Text(provider.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Offline Toast

    @ViewBuilder
    private var offlineToast: some View {
        VStack {
            Text("No internet \u{2014} using local translation")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 70)
            Spacer()
        }
    }

    // MARK: - Language Picker

    private func languagePickerSheet(
        title: String,
        selection: Binding<String>,
        showAutoDetect: Bool
    ) -> some View {
        NavigationStack {
            List {
                if showAutoDetect {
                    Button {
                        selection.wrappedValue = ""
                        dismissPicker(title)
                    } label: {
                        HStack {
                            Text("Auto-detect").foregroundStyle(.primary)
                            Spacer()
                            if selection.wrappedValue.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }

                ForEach(SupportedLanguage.all) { language in
                    Button {
                        selection.wrappedValue = language.id
                        dismissPicker(title)
                    } label: {
                        HStack {
                            Text(language.displayName).foregroundStyle(.primary)
                            Spacer()
                            if selection.wrappedValue == language.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismissPicker(title) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func dismissPicker(_ title: String) {
        if title == "Source Language" {
            showSourcePicker = false
        } else {
            showTargetPicker = false
        }
    }

    // MARK: - Permission Denied

    @ViewBuilder
    private var permissionDeniedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
                Text("Camera Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Cera needs camera access to detect and translate text. Please enable it in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch viewModel.state {
        case .idle:          .gray
        case .recognizing:   .yellow
        case .translating:   .blue
        case .summarizing:   .purple
        case .done:          .green
        case .error:         .red
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle:             "Ready"
        case .recognizing:      "Scanning…"
        case .translating:      "Translating…"
        case .summarizing:      "Summarizing…"
        case .done:             "Done"
        case .error(let msg):   msg
        }
    }

    private func updateTranslationConfig() {
        translationConfig.source = viewModel.sourceLanguageCode.isEmpty
            ? nil
            : Locale.Language(identifier: viewModel.sourceLanguageCode)
        translationConfig.target = Locale.Language(identifier: viewModel.targetLanguageCode)
        translationConfig.invalidate()
    }
}
