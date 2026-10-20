import Foundation

/// Familles d'informations que l'utilisateur peut activer ou non.
enum Category: String, CaseIterable, Codable {
    case contacts, banking, secrets, notifications

    var title: String {
        switch self {
        case .contacts: return "E-mails et téléphones"
        case .banking: return "Banque et paiements"
        case .secrets: return "Mots de passe et codes"
        case .notifications: return "Notifications"
        }
    }

    var detail: String {
        switch self {
        case .contacts: return "Adresses e-mail, numéros français et internationaux"
        case .banking: return "IBAN, numéros de carte, montants sur les pages bancaires"
        case .secrets: return "Codes de vérification, clés d'API, mots de passe affichés"
        case .notifications: return "Les bannières qui apparaissent en haut à droite"
        }
    }
}

/// Ce qui a été trouvé dans une ligne de texte.
enum Kind: String {
    case email, phone, iban, card, amount, secret, password, code

    var category: Category {
        switch self {
        case .email, .phone: return .contacts
        case .iban, .card, .amount: return .banking
        case .secret, .password, .code: return .secrets
        }
    }

    var label: String {
        switch self {
        case .email: return "e-mail"
        case .phone: return "téléphone"
        case .iban: return "IBAN"
        case .card: return "carte"
        case .amount: return "montant"
        case .secret: return "clé"
        case .password: return "mot de passe"
        case .code: return "code"
        }
    }

    /// Plus le chiffre est petit, plus la détection est prioritaire en cas de chevauchement.
    var priority: Int {
        switch self {
        case .secret: return 0
        case .password: return 1
        case .iban: return 2
        case .card: return 3
        case .email: return 4
        case .phone: return 5
        case .code: return 6
        case .amount: return 7
        }
    }
}

struct Finding: Equatable {
    let kind: Kind
    let range: NSRange  // en UTF-16, dans la ligne analysée
    let text: String
}

/// Indices tirés de tout l'écran (une page bancaire ? un code à saisir ?).
struct ScreenContext {
    var bankingPage = false
}

enum Detectors {
    // MARK: - Expressions

    private static func rx(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private static let email = rx(#"[A-Za-z0-9._%+\-]+ ?@ ?[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}"#)
    private static let phoneFR = rx(#"(?<![\w+])(?:\+33 ?(?:\(0\) ?)?|0033 ?|0)[1-9](?:[ .\-]?\d{2}){4}(?!\w)"#)
    private static let phoneIntl = rx(#"(?<![\w+])\+\d{1,3}[ .\-]?(?:\(\d{1,4}\)[ .\-]?)?\d{1,4}(?:[ .\-]?\d{2,4}){2,4}(?!\w)"#)
    private static let iban = rx(#"(?<![A-Za-z0-9])[A-Z]{2} ?\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?(?![A-Za-z0-9])"#)
    private static let card = rx(#"(?<![\w.,])(?:\d[ \-]?){12,18}\d(?![\w,])"#)
    private static let amount = rx(#"(?:[-+−] ?)?(?:\d{1,3}(?:[ .\x{202F}\x{00A0}]\d{3})+|\d+)(?:[,.]\d{2})? ?(?:€|EUR)|(?:€|\$|£) ?\d[\d ,.\x{202F}\x{00A0}]*\d"#)
    /// Sur une page bancaire, un nombre à virgule suffit (la lecture rapide perd souvent le « € »).
    private static let decimalAmount = rx(#"(?<![\w.,/:])[-+−]? ?\d{1,3}(?:[ .\x{202F}\x{00A0}]\d{3})*,\d{2}(?![\d,])"#)
    private static let otp = rx(#"(?<![\w.,/:€$£])(?:\d{3}[ \-]\d{3}|\d{4,8})(?![\w.,/:€%])"#)
    private static let knownSecret = rx(
        #"(?:sk-[A-Za-z0-9_\-]{20,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}|"#
        + #"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_\-]{20,}|"#
        + #"xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{30,}|"#
        + #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}|"#
        + #"-----BEGIN [A-Z ]*PRIVATE KEY-----)"#)
    /// « Mot de passe : xxx », « password=xxx », « CVV 123 »…
    private static let labelled = rx(
        #"\b(?:mot de passe|mots de passe|password|passwd|pwd|mdp|code pin|pin|passcode|cvv|cvc|cryptogramme|"#
        + #"secret|token|api[ _\-]?key|clé (?:api|secrète))\s*[:=]\s*["'«]?\s*([^\s"'»]{3,})"#,
        [.caseInsensitive])
    /// Variables d'environnement : DB_PASSWORD=…, STRIPE_SECRET_KEY: …
    private static let envSecret = rx(
        #"[A-Za-z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_KEY|ACCESS_KEY)[A-Za-z0-9_]*\s*[:=]\s*["']?([^\s"']{4,})"#,
        [.caseInsensitive])
    private static let longToken = rx(#"(?<![A-Za-z0-9+/_\-])[A-Za-z0-9+/_\-]{32,}={0,2}(?![A-Za-z0-9+/_\-])"#)

    private static let bankWords = rx(
        #"\b(?:solde|iban|rib|virements?|prélèvements?|livret|découvert|relevés?|épargne|"#
        + #"compte (?:courant|joint|chèques?|titres)|mes comptes|carte bancaire|bic|"#
        + #"available balance|account balance|bank transfer)\b"#, [.caseInsensitive])
    private static let codeWords = rx(
        #"(?:\bcodes?\b|\botp\b|vérification|verification|confirmation|\b2fa\b|authentification|authentication|"#
        + #"usage unique|one[- ]time|passcode|sécurité|security|connexion|login|validation)"#, [.caseInsensitive])
    private static let cardWords = rx(#"\b(?:carte|card|cb|visa|mastercard|amex|american express|paiement|payment)\b"#,
                                      [.caseInsensitive])
    private static let tokenWords = rx(#"(?:key|token|secret|clé|api|bearer|authorization|password|private)"#,
                                       [.caseInsensitive])

    // MARK: - Analyse

    static func context(for lines: [String]) -> ScreenContext {
        var ctx = ScreenContext()
        for l in lines where has(bankWords, l) {
            ctx.bankingPage = true
            break
        }
        return ctx
    }

    /// Analyse toutes les lignes d'un écran. Les lignes voisines servent d'indices (ex. « Votre code » au-dessus).
    static func scan(lines: [String], enabled: Set<Category>) -> [[Finding]] {
        let ctx = context(for: lines)
        return lines.indices.map { i in
            let around = [i > 0 ? lines[i - 1] : "", lines[i], i + 1 < lines.count ? lines[i + 1] : ""]
                .joined(separator: " \n ")
            return scan(lines[i], around: around, context: ctx, enabled: enabled)
        }
    }

    static func scan(_ line: String, around: String? = nil, context: ScreenContext = ScreenContext(),
                     enabled: Set<Category> = Set(Category.allCases)) -> [Finding] {
        let around = around ?? line
        var found: [Finding] = []
        let ns = line as NSString

        func add(_ kind: Kind, _ r: NSRange) {
            guard enabled.contains(kind.category), r.location != NSNotFound, r.length > 0 else { return }
            found.append(Finding(kind: kind, range: r, text: ns.substring(with: r)))
        }
        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) { body(m) }
        }

        // Secrets
        each(knownSecret) { add(.secret, $0.range) }
        each(envSecret) { add(.password, $0.range(at: 1)) }
        each(labelled) { m in
            let value = ns.substring(with: m.range(at: 1))
            // « Mot de passe oublié ? » n'est pas un mot de passe
            let lower = value.lowercased()
            if ["oublié", "oublié ?", "oublié?", "forgotten", "forgot", "incorrect", "requis", "required",
                "actuel", "nouveau", "new", "current", "manager", "managers", "reset", "réinitialiser",
                "masqué", "hidden", "et", "and", "ou", "or"].contains(lower) { return }
            if lower.hasPrefix("oubli") || lower.hasPrefix("forgot") { return }
            if value.allSatisfy({ $0 == "•" || $0 == "*" || $0 == "●" || $0 == "·" }) { return }
            add(.password, m.range(at: 1))
        }
        if has(tokenWords, around) {
            each(longToken) { m in
                let t = ns.substring(with: m.range)
                if looksRandom(t) { add(.secret, m.range) }
            }
        }

        // Banque
        each(iban) { m in
            let raw = ns.substring(with: m.range).replacingOccurrences(of: " ", with: "")
            guard raw.count >= 15, raw.count <= 34 else { return }
            if ibanChecksumOK(raw) || around.range(of: "IBAN", options: .caseInsensitive) != nil
                || around.range(of: "RIB") != nil {
                add(.iban, m.range)
            }
        }
        each(card) { m in
            let digits = ns.substring(with: m.range).filter(\.isNumber)
            guard (13...19).contains(digits.count) else { return }
            if luhn(digits) || (digits.count == 16 && has(cardWords, around)) { add(.card, m.range) }
        }
        if context.bankingPage {
            each(amount) { add(.amount, $0.range) }
            each(decimalAmount) { add(.amount, $0.range) }
        }

        // Contacts
        each(email) { add(.email, $0.range) }
        each(phoneFR) { add(.phone, $0.range) }
        each(phoneIntl) { m in
            let n = ns.substring(with: m.range).filter(\.isNumber).count
            if (8...15).contains(n) { add(.phone, m.range) }
        }

        // Codes à usage unique : seulement s'il y a un indice autour
        if has(codeWords, around) {
            each(otp) { m in
                let t = ns.substring(with: m.range)
                let digits = t.filter(\.isNumber)
                if digits.count == 4, let y = Int(digits), (1900...2099).contains(y) { return }  // une année
                add(.code, m.range)
            }
        }

        return resolveOverlaps(found)
    }

    // MARK: - Aides

    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func resolveOverlaps(_ list: [Finding]) -> [Finding] {
        var kept: [Finding] = []
        for f in list.sorted(by: { ($0.kind.priority, -$0.range.length) < ($1.kind.priority, -$1.range.length) }) {
            if kept.contains(where: { NSIntersectionRange($0.range, f.range).length > 0 }) { continue }
            kept.append(f)
        }
        return kept.sorted { $0.range.location < $1.range.location }
    }

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }

    static func ibanChecksumOK(_ iban: String) -> Bool {
        let s = iban.uppercased()
        guard s.count >= 15 else { return false }
        let rearranged = s.dropFirst(4) + s.prefix(4)
        var rem = 0
        for ch in rearranged {
            if let d = ch.wholeNumberValue {
                rem = (rem * 10 + d) % 97
            } else if let a = ch.asciiValue, a >= 65, a <= 90 {
                rem = (rem * 100 + Int(a) - 55) % 97
            } else {
                return false
            }
        }
        return rem == 1
    }

    /// Un long jeton qui ressemble à une clé : mélange de minuscules, majuscules et chiffres.
    static func looksRandom(_ t: String) -> Bool {
        let lower = t.contains { $0.isLowercase }
        let upper = t.contains { $0.isUppercase }
        let digit = t.contains { $0.isNumber }
        guard digit && (lower || upper) && (lower && upper || t.count >= 40) else { return false }
        // pas un chemin ou un mot composé courant
        return !t.contains("__") && Set(t).count >= 12
    }
}
