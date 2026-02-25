//
//  OCRService.swift
//  Cera
//
//  Created by Oskar Pajka on 25/02/2026.
//

import Vision
import CoreVideo

/// Performs text recognition on camera frames using the Vision framework.
final class OCRService: Sendable {

    private let minimumConfidence: Float = 0.3

    /// Recognizes text in the given pixel buffer.
    func recognizeText(
        from pixelBuffer: CVPixelBuffer,
        languages: [String]? = nil
    ) async throws -> [RecognizedTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = ContinuationGuard()

            let request = VNRecognizeTextRequest { request, error in
                guard resumed.claim() else { return }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let blocks = observations.compactMap { observation -> RecognizedTextBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    guard candidate.confidence >= self.minimumConfidence else { return nil }
                    return RecognizedTextBlock(text: candidate.string, confidence: candidate.confidence)
                }
                continuation.resume(returning: blocks)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let languages {
                request.recognitionLanguages = languages
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
