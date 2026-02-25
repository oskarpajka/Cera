//
//  SceneClassifier.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import Vision
import CoreVideo

/// Classifies the visual scene of a camera frame using Vision's built-in
/// image classification model. The resulting labels are fed to the LLM
/// as hints for generating a human-readable scene description.
final class SceneClassifier: Sendable {

    private let confidenceThreshold: Float = 0.15
    private let maxLabels: Int = 3

    /// Returns the top classification labels for the given pixel buffer.
    func classify(from pixelBuffer: CVPixelBuffer) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = ContinuationGuard()

            let request = VNClassifyImageRequest { request, error in
                guard resumed.claim() else { return }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let labels = results
                    .filter { $0.confidence >= self.confidenceThreshold }
                    .prefix(self.maxLabels)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

                continuation.resume(returning: Array(labels))
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guard resumed.claim() else { return }
                continuation.resume(throwing: error)
            }
        }
    }
}
