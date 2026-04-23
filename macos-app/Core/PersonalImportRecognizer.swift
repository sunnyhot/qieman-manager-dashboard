import AppKit
import Foundation
import Vision

enum PersonalImportError: LocalizedError {
    case imageLoadFailed(String)
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let path):
            return "无法读取图片：\(path)"
        case .ocrFailed(let message):
            return "图片文字识别失败：\(message)"
        }
    }
}

final class PersonalImportRecognizer {
    func recognizeText(from fileURL: URL) async throws -> String {
        guard let image = NSImage(contentsOf: fileURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PersonalImportError.imageLoadFailed(fileURL.path)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: PersonalImportError.ocrFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continuation.resume(returning: lines.filter { !$0.isEmpty }.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: PersonalImportError.ocrFailed(error.localizedDescription))
            }
        }
    }
}
