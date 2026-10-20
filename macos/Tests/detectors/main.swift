import Foundation

// Tests des détecteurs d'AikoShield (compilés avec Sources/Detectors.swift, sans interface).

var failures: [String] = []

func expect(_ line: String, _ kinds: [Kind], masked: [String] = [], around: String? = nil, bank: Bool = false) {
    var ctx = ScreenContext()
    ctx.bankingPage = bank
    let found = Detectors.scan(line, around: around, context: ctx)
    let got = found.map(\.kind)
    var ok = got == kinds
    for m in masked where !found.contains(where: { $0.text == m }) { ok = false }
    let desc = found.map { "\($0.kind.rawValue)「\($0.text)」" }.joined(separator: " ")
    print((ok ? "  ok   " : "  FAIL ") + line + "  →  " + (desc.isEmpty ? "rien" : desc))
    if !ok {
        failures.append("\(line) — attendu \(kinds.map(\.rawValue)) \(masked), reçu \(desc)")
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil {
            print("::error title=Détecteur::\(line) → \(desc.isEmpty ? "rien" : desc)")
        }
    }
}

print("== Contacts")
expect("Contact : baptiste.dupont@gmail.com", [.email], masked: ["baptiste.dupont@gmail.com"])
expect("Écris à contact@aikographic.com ou au 06 12 34 56 78", [.email, .phone], masked: ["06 12 34 56 78"])
expect("Tél +33 6 12 34 56 78", [.phone], masked: ["+33 6 12 34 56 78"])
expect("Bureau : 01.23.45.67.89", [.phone], masked: ["01.23.45.67.89"])
expect("Portable 0612345678", [.phone])
expect("UK office +44 20 7946 0958", [.phone], masked: ["+44 20 7946 0958"])
expect("Page 12 sur 345 — 19/10/2026 14:03", [])
expect("Commande n° 2024-10-19-8812", [])

print("== Banque")
expect("IBAN FR76 3000 6000 0112 3456 7890 189", [.iban], masked: ["FR76 3000 6000 0112 3456 7890 189"])
expect("GB82 WEST 1234 5698 7654 32", [.iban])  // somme de contrôle valide, sans le mot IBAN
expect("Carte 4970 1012 3456 7890", [.card], masked: ["4970 1012 3456 7890"])  // indice « carte »
expect("4111 1111 1111 1111", [.card])  // Luhn valide
expect("Numéro de suivi 1234 5678 9012 3456", [])  // ni Luhn ni mot « carte »
expect("Solde : 1 234,56 €", [.amount], masked: ["1 234,56 €"], bank: true)
expect("Virement -45,00 € à Marie", [.amount], bank: true)
expect("Prix : 49,99 €", [], bank: false)  // hors page bancaire, les prix restent visibles
expect("CVV : 123", [.password], masked: ["123"])

print("== Mots de passe et codes")
expect("OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz123456", [.secret])
expect("token ghp_abcdefghijklmnopqrstuvwxyz0123456789", [.secret])
expect("aws AKIAIOSFODNN7EXAMPLE", [.secret])
expect("DB_PASSWORD=Sup3rS3cret!", [.password], masked: ["Sup3rS3cret!"])
expect("Mot de passe : Hunter2!", [.password], masked: ["Hunter2!"])
expect("password=abc123", [.password], masked: ["abc123"])
expect("Mot de passe oublié ?", [])
expect("Mot de passe : ••••••••", [])
expect("Votre code de vérification est 482 913", [.code], masked: ["482 913"])
expect("G-582913 est votre code Google", [.code])
expect("582913", [.code], around: "Votre code de connexion\n582913")
expect("Bonjour, rendez-vous à 14h30 le 19/10", [])
expect("Authorization: Bearer aZ9kP2xQ7rT4vB8nM3wL6yH1jF5gD0sC", [.secret])
expect("Le code postal 75011 Paris", [.code])  // accepté : « code » + 5 chiffres (mieux vaut trop masquer)

print("== Contrôles")
let luhnOK = Detectors.luhn("4970101234567890") == false && Detectors.luhn("4111111111111111")
print(luhnOK ? "  ok   Luhn" : "  FAIL Luhn")
if !luhnOK { failures.append("Luhn") }
let ibanOK = Detectors.ibanChecksumOK("FR7630006000011234567890189") && !Detectors.ibanChecksumOK("FR7630006000011234567890188")
print(ibanOK ? "  ok   IBAN mod 97" : "  FAIL IBAN mod 97")
if !ibanOK { failures.append("IBAN mod 97") }

let screen = ["Mes comptes", "Compte courant", "Solde 2 450,10 €", "Netflix -13,49 €", "Votre code", "839 201"]
let all = Detectors.scan(lines: screen, enabled: [.banking, .secrets])
let kinds = all.flatMap { $0.map(\.kind) }
let screenOK = kinds == [.amount, .amount, .code]
print((screenOK ? "  ok   " : "  FAIL ") + "écran bancaire complet → \(kinds.map(\.rawValue))")
if !screenOK { failures.append("écran complet") }
let off = Detectors.scan(lines: ["jean@exemple.fr"], enabled: [.banking])
let offOK = off.flatMap { $0 }.isEmpty
print((offOK ? "  ok   " : "  FAIL ") + "catégorie désactivée → rien de masqué")
if !offOK { failures.append("catégorie désactivée") }

if failures.isEmpty {
    print("\nTout est OK")
    exit(0)
}
print("\nÉCHECS :\n" + failures.joined(separator: "\n"))
exit(1)
