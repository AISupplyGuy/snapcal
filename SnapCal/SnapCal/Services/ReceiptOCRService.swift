import CoreGraphics
import Foundation
import UIKit
import Vision

// Wraps VNRecognizeTextRequest for receipt photos. Runs on the cheap
// .accurate path with USR/EN language correction, returns the raw text
// lines in roughly top-to-bottom reading order so the classifier can
// turn them into pantry candidates.
enum ReceiptOCRService {
    static func recognizeLines(in images: [UIImage]) async throws -> [String] {
        var collected: [String] = []
        for image in images {
            let lines = try await recognize(in: image)
            collected.append(contentsOf: lines)
        }
        return collected
    }

    private static func recognize(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Sort top-to-bottom (Vision uses normalized coords with origin
                // at bottom-left, so larger y == higher on the page) then
                // left-to-right within a row.
                let ordered = observations.sorted { lhs, rhs in
                    let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
                    if abs(dy) > 0.01 { return dy > 0 }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                let lines = ordered.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
