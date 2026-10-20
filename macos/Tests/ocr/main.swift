import AppKit
import Vision

// Test de bout en bout sans écran : on dessine une fausse page, Vision la lit, on vérifie ce qui serait masqué,
// puis on enregistre l'image avec les masques (dossier screenshots/).

var failures: [String] = []
let ci = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "screenshots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct Block { let title: String; let lines: [String] }
let blocks: [Block] = [
    Block(title: "CONTACTS", lines: ["E-mail   camille.martin@exemple.fr", "Portable   06 12 34 56 78",
                                     "Bureau   +33 1 23 45 67 89", "Londres   +44 20 7946 0958"]),
    Block(title: "MES COMPTES", lines: ["Compte courant · Solde   2 450,10 €", "Livret A   8 120,00 €",
                                        "Virement Netflix   -13,49 €", "IBAN   FR76 3000 6000 0112 3456 7890 189",
                                        "Carte   4970 1012 3456 7890"]),
    Block(title: "CODES ET ACCÈS", lines: ["Votre code de vérification", "482 913", "Mot de passe : Soleil-Rouge-42"]),
    Block(title: "FICHIER .ENV", lines: ["OPENAI_API_KEY=sk-proj-Xa82kd0Qp1LmZ7ve3nRt5Ybh", "DB_PASSWORD=Pr0d!Pass2026",
                                         "GITHUB_TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"]),
]
let mustStay = "Réunion du 19/10/2026 à 14h30 — page 12 sur 345"
// clés et mots de passe comptés ensemble : « ghp_… » lu « ghp … » reste masqué comme valeur de GITHUB_TOKEN
let expected: [Kind: Int] = [.email: 1, .phone: 3, .amount: 3, .iban: 1, .card: 1, .code: 1, .secret: 4]

func render(dark: Bool) -> (CGImage, CGRect) {
    let W = 2000, H = 1100
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bg = dark ? NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1) : .white
    let surface = dark ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
                       : NSColor(srgbRed: 0.95, green: 0.97, blue: 0.99, alpha: 1)
    let ink = dark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.05, alpha: 1)
    let accent = dark ? Theme.accent : Theme.accentDeep
    bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: ink]
    let head: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                                               .foregroundColor: accent]
    ("Page de test AikoShield" as NSString).draw(at: NSPoint(x: 80, y: H - 110), withAttributes: [
        .font: NSFont.systemFont(ofSize: 48, weight: .bold), .foregroundColor: ink])
    for (i, b) in blocks.enumerated() {
        let x = CGFloat(80 + (i % 2) * 940), top = CGFloat(H - 190 - (i / 2) * 400)
        let card = NSRect(x: x - 30, y: top - 70 - CGFloat(b.lines.count) * 56, width: 900,
                          height: 100 + CGFloat(b.lines.count) * 56)
        surface.setFill()
        NSBezierPath(roundedRect: card, xRadius: 24, yRadius: 24).fill()
        (b.title as NSString).draw(at: NSPoint(x: x, y: top - 40), withAttributes: head)
        for (j, l) in b.lines.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = l == "482 913"
                ? [.font: NSFont.systemFont(ofSize: 52, weight: .semibold), .foregroundColor: ink] : body
            (l as NSString).draw(at: NSPoint(x: x, y: top - 100 - CGFloat(j) * 56), withAttributes: attrs)
        }
    }
    let stayPoint = NSPoint(x: 80, y: 60)
    (mustStay as NSString).draw(at: stayPoint, withAttributes: body)
    let stayRect = CGRect(origin: stayPoint, size: (mustStay as NSString).size(withAttributes: body))
    NSGraphicsContext.restoreGraphicsState()
    let norm = CGRect(x: stayRect.minX / CGFloat(W), y: stayRect.minY / CGFloat(H),
                      width: stayRect.width / CGFloat(W), height: stayRect.height / CGFloat(H))
    return (rep.cgImage!, norm)
}

func save(_ image: CGImage, _ found: [Detection], _ name: String, dark: Bool) {
    let W = image.width, H = image.height
    let rep = NSBitmapImageRep(cgImage: image)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for d in found {
        let r = CGRect(x: d.box.minX * CGFloat(W), y: d.box.minY * CGFloat(H),
                       width: d.box.width * CGFloat(W), height: d.box.height * CGFloat(H)).insetBy(dx: -10, dy: -6)
        let p = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        Theme.maskFill(dark: dark).setFill()
        p.fill()
        Theme.maskInk(dark: dark).setStroke()
        p.lineWidth = 2
        p.stroke()
        let t = "\(d.kind.label) masqué" as NSString
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: min(24, r.height * 0.5), weight: .semibold),
                                                .foregroundColor: Theme.maskInk(dark: dark)]
        let s = t.size(withAttributes: a)
        if s.width < r.width { t.draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2), withAttributes: a) }
    }
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent(name))
}

for precise in [false, true] {
    for dark in [false, true] {
        let mode = (precise ? "precis" : "rapide") + "-" + (dark ? "sombre" : "clair")
        let (image, stay) = render(dark: dark)
        let t0 = CFAbsoluteTimeGetCurrent()
        let found = Recognizer.detect(in: VNImageRequestHandler(cgImage: image, options: [:]),
                                      precise: precise, enabled: Set(Category.allCases))
        let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        print("== \(mode) (\(ms) ms)")
        for d in found { print("   \(d.kind.rawValue)「\(d.text)」") }
        if ci {
            print("::notice title=OCR \(mode) \(ms) ms::" + found.map { "\($0.kind.rawValue)「\($0.text)」" }.joined(separator: " "))
        }
        var counts: [Kind: Int] = [:]
        for d in found { counts[d.kind == .password ? .secret : d.kind, default: 0] += 1 }
        var problems: [String] = []
        for (k, n) in expected.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where (counts[k] ?? 0) < n {
            problems.append("\(k.rawValue) : \(counts[k] ?? 0)/\(n)")
        }
        if found.contains(where: { $0.box.intersects(stay) }) { problems.append("texte ordinaire masqué à tort") }
        if problems.isEmpty {
            print("  ok   tout est repéré")
        } else {
            let msg = "\(mode) — manque : " + problems.joined(separator: ", ")
            print("  " + (precise ? "FAIL " : "AVERT ") + msg)
            if precise { failures.append(msg) }
            if ci { print("::\(precise ? "error" : "warning") title=OCR::\(msg)") }
        }
        save(image, found, "ocr-\(mode).png", dark: dark)
    }
}

let pieces = subtractRects(CGRect(x: 0, y: 0, width: 100, height: 100), [CGRect(x: 50, y: 50, width: 100, height: 100)])
let area = pieces.reduce(0) { $0 + $1.width * $1.height }
let geoOK = abs(area - 7500) < 0.1
print((geoOK ? "  ok   " : "  FAIL ") + "partie visible d'une fenêtre recouverte (\(Int(area)) / 7500)")
if !geoOK { failures.append("géométrie") }

if failures.isEmpty { print("\nTout est OK"); exit(0) }
print("\nÉCHECS :\n" + failures.joined(separator: "\n"))
exit(1)
