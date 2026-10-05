import Vision
import UIKit

/// Reads the text in a photo. Behind a protocol so the review screen can be tested without Vision.
protocol TextRecognizer {
    /// - Parameter orientation: how the photo's pixels are turned. A portrait camera photo's
    ///   `CGImage` is stored sideways; without this, Vision reads columns instead of lines.
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [TextFragment]
}

/// Apple's on-device text recognition. The photo never leaves the phone.
struct VisionTextRecognizer: TextRecognizer {
    func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [TextFragment] {
        // `perform` blocks for a second or more on a photo, so it runs off the main actor.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                // Receipts are codes and abbreviations, which "correction" would turn into words.
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                do {
                    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
                    let fragments = (request.results ?? []).compactMap { observation -> TextFragment? in
                        guard let text = observation.topCandidates(1).first?.string else { return nil }
                        return TextFragment(text: text, box: observation.boundingBox)
                    }
                    continuation.resume(returning: fragments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
