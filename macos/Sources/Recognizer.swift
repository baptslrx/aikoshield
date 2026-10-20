import CoreGraphics
import Foundation
import Vision

/// Une zone à masquer, en coordonnées normalisées de l'image (0…1, origine en bas à gauche).
struct Detection {
    let kind: Kind
    let box: CGRect
    let text: String
}

/// Lecture du texte à l'écran (Vision, 100 % sur le Mac) puis recherche des infos sensibles.
enum Recognizer {
    static func detect(in handler: VNImageRequestHandler, precise: Bool, enabled: Set<Category>) -> [Detection] {
        let textCategories = enabled.subtracting([.notifications])
        guard !textCategories.isEmpty else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = precise ? .accurate : .fast
        request.usesLanguageCorrection = false  // la correction « réparerait » les e-mails et les numéros
        if precise { request.recognitionLanguages = ["fr-FR", "en-US"] }
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let pairs: [(box: CGRect, text: VNRecognizedText)] = (request.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            return (obs.boundingBox, c)
        }
        let texts = pairs.map(\.text.string)
        let ctx = Detectors.context(for: texts)
        // Indices autour d'une ligne : les lignes proches au-dessus / en dessous, dans la même colonne
        let results: [[Finding]] = pairs.indices.map { i in
            let a = pairs[i].box
            var around = [texts[i]]
            for j in pairs.indices where j != i {
                let b = pairs[j].box
                let gap = max(b.minY - a.maxY, a.minY - b.maxY)
                let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                let sameColumn = gap < max(a.height, b.height) * 2.5 && overlapX > -0.02
                let sameRow = gap < 0 && overlapX > -0.25
                if sameColumn || sameRow { around.append(texts[j]) }
            }
            return Detectors.scan(texts[i], around: around.joined(separator: " \n "), context: ctx,
                                  enabled: textCategories)
        }
        let lines = pairs.map(\.text)

        var out: [Detection] = []
        for (candidate, findings) in zip(lines, results) {
            for f in findings {
                guard let range = Range(f.range, in: candidate.string) else { continue }
                if let r = try? candidate.boundingBox(for: range)?.boundingBox {
                    out.append(Detection(kind: f.kind, box: r, text: f.text))
                }
            }
        }
        return out
    }
}
