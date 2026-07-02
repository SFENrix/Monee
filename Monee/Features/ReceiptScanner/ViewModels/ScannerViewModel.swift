//
//  ScannerViewModel.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  ScannerViewModel.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Orchestrates the OCR pipeline: image in -> VisionOCRService -> RegexParser -> ParsedReceiptData.
//  Deliberately does NOT touch SwiftData or persistence — ReceiptConfirmationView owns turning
//  the parsed result into a Transaction (via QuickEntryViewModel), same separation of concerns
//  as ManualEntry.
//

import Foundation
import UIKit
import Combine

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var parsedData: ParsedReceiptData?
    @Published var capturedImage: UIImage?

    /// Runs the full pipeline for a captured/picked image.
    func processImage(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil
        capturedImage = image
        parsedData = nil

        do {
            let rawText = try await VisionOCRService.recognizeText(from: image)
            parsedData = RegexParser.parse(rawText)
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    /// Clears state so the view can go back to the capture step (e.g. after a failed scan
    /// or the user wants to try a different photo).
    func reset() {
        isProcessing = false
        errorMessage = nil
        parsedData = nil
        capturedImage = nil
    }
}
