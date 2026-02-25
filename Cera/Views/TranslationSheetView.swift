//
//  TranslationSheetView.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import SwiftUI

// MARK: - Translation Sheet

/// Bottom sheet displaying translation results.
///
/// Layout order (top to bottom):
/// 1. Back button (closes sheet)
/// 2. Scene description (gray)
/// 3. AI summary / translation (white, primary)
/// 4. Scan Again button
/// 5. Original detected text (secondary)
///
/// Draggable: collapsed (~32%) ↔ expanded (full screen).
struct TranslationSheetView: View {
    let summaryText: String?
    let fallbackTranslation: String
    let originalText: String
    let sceneDescription: String
    let state: TranslationState
    let onClose: () -> Void

    @State private var sheetOffset: CGFloat = 0
    @State private var isExpanded = false

    private let collapsedFraction: CGFloat = 0.32

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let collapsedHeight = screenHeight * collapsedFraction
            let expandedHeight = screenHeight - geometry.safeAreaInsets.top
            let targetHeight = isExpanded ? expandedHeight : collapsedHeight

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    dragHandle

                    ScrollView(.vertical, showsIndicators: false) {
                        sheetContent
                            .padding(.horizontal, 20)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                    }
                }
                .frame(height: clampedHeight(target: targetHeight, offset: sheetOffset))
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                        .fill(.ultraThickMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 20, y: -4)
                )
                .gesture(sheetDrag(collapsed: collapsedHeight, expanded: expandedHeight))
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(.secondary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    // MARK: - Content

    @ViewBuilder
    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 14) {

            // 1. Back button
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Back")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }

            // 2. Scene description
            if !sceneDescription.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.caption2)
                    Text(sceneDescription)
                        .font(.caption)
                }
                .foregroundStyle(.gray)
            }

            // Processing indicator
            processingIndicator

            // 3. AI summary or fallback translation (primary)
            if let summary = summaryText {
                Text(summary)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !fallbackTranslation.isEmpty {
                Text(fallbackTranslation)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 4. Scan Again button
            Button {
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("Scan Again")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }

            // 5. Original text (last)
            if !originalText.isEmpty {
                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(originalText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Processing Indicator

    @ViewBuilder
    private var processingIndicator: some View {
        switch state {
        case .recognizing, .translating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .summarizing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Summarizing…")
                    .font(.caption)
                    .foregroundStyle(.purple.opacity(0.8))
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func clampedHeight(target: CGFloat, offset: CGFloat) -> CGFloat {
        max(target - offset, 40)
    }

    private func sheetDrag(collapsed: CGFloat, expanded: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                sheetOffset = value.translation.height
            }
            .onEnded { value in
                let dy = value.translation.height
                let velocity = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isExpanded {
                        // Expanded → collapse on downward drag
                        if dy > 80 || velocity > 400 {
                            isExpanded = false
                        }
                    } else {
                        // Collapsed → expand on upward drag
                        if dy < -60 || velocity < -300 {
                            isExpanded = true
                        }
                        // Collapsed → dismiss on strong downward drag
                        if dy > 80 || velocity > 500 {
                            onClose()
                        }
                    }
                    sheetOffset = 0
                }
            }
    }
}
