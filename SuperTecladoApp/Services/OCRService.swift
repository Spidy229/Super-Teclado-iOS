import UIKit
import Vision

enum OCRService {
    static func recognizeText(in data: Data) async -> String? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(returning: text.isEmpty ? nil : text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["es-ES", "en-US"]

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

