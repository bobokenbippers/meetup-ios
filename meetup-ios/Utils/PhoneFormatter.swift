import Foundation

enum PhoneFormatter {
    /// Format raw input as `(XXX) XXX-XXXX` — strips non-digits, caps at 10.
    static func format(_ rawInput: String) -> String {
        let digits = String(rawInput.filter { $0.isNumber }.prefix(10))
        return formatDigits(digits, prefix: "")
    }

    /// Format a digits-only string as `+1 (XXX) XXX-XXXX` — used in friend search.
    static func formatWithCountryCode(_ digits: String) -> String {
        return formatDigits(String(digits.prefix(10)), prefix: "+1 ")
    }

    /// Normalize any formatted phone string to E.164 `+1XXXXXXXXXX`.
    /// Returns nil if fewer than 10 digits are present.
    static func toE164(_ input: String) -> String? {
        let raw = input.hasPrefix("+1") ? String(input.dropFirst(2)) : input
        let digits = raw.filter { $0.isNumber }
        guard digits.count == 10 else { return nil }
        return "+1" + digits
    }

    private static func formatDigits(_ digits: String, prefix: String) -> String {
        switch digits.count {
        case 0:     return ""
        case 1...3: return "\(prefix)(\(digits)"
        case 4...6: return "\(prefix)(\(digits.prefix(3))) \(digits.dropFirst(3))"
        default:    return "\(prefix)(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
        }
    }
}
