//
//  VisionOCRServiceError.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  VisionOCRService.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Thin wrapper around Apple's Vision framework. Its only job is image -> raw text;
//  RegexParser (already done) takes it from there. Kept this dumb on purpose — no
//  business logic here, so it's easy to swap recognition strategies later without
//  touching anything downstream.
//

import Foundation
import Vision
import UIKit

enum VisionOCRServiceError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "That doesn't look like a valid image."
        case .recognitionFailed(let reason):
            return "Text recognition failed: \(reason)"
        case .noTextFound:
            return "Couldn't find any readable text in that photo."
        }
    }
}

enum VisionOCRService {

    /// Runs on-device text recognition over the given image and returns the raw extracted text,
    /// one line per recognized text block, top-to-bottom as Vision found them.
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw VisionOCRServiceError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionOCRServiceError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: VisionOCRServiceError.noTextFound)
                    return
                }

                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: VisionOCRServiceError.noTextFound)
                } else {
                    continuation.resume(returning: text)
                }
            }

            // .accurate over .fast — receipts are dense, small-font text where accuracy
            // matters more than the ~2x speed difference. Language correction helps with
            // OCR noise on merchant names, but can occasionally "fix" a genuine typo — worth
            // re-evaluating once we test against real receipts.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: VisionOCRServiceError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}