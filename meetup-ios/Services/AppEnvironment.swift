import Foundation

struct AppEnvironment {
    static let current = AppEnvironment()

    private let values: [String: String]

    init(raw: String? = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            values = [:]
            return
        }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
            return
        }

        values = Self.parseKeyValuePairs(trimmed)
    }

    func value(for key: String) -> String? {
        guard let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("$(")
        else {
            return nil
        }
        return value
    }

    private static func parseKeyValuePairs(_ raw: String) -> [String: String] {
        raw
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, line in
                let trimmedLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty,
                      !trimmedLine.hasPrefix("#"),
                      let equals = trimmedLine.firstIndex(of: "=")
                else {
                    return
                }

                let key = trimmedLine[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = trimmedLine[trimmedLine.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }

                result[key] = rawValue.trimmingMatchingQuotes()
            }
    }
}

private extension String {
    func trimmingMatchingQuotes() -> String {
        guard count >= 2,
              let first,
              let last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return self
        }
        return String(dropFirst().dropLast())
    }
}
