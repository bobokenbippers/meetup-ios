import Testing
@testable import meetup_ios

@Suite("PhoneFormatter")
struct PhoneFormatterTests {

    // MARK: - format (no country code)

    @Test("empty string returns empty")
    func formatEmpty() {
        #expect(PhoneFormatter.format("") == "")
    }

    @Test("1-3 digits show partial area code")
    func formatPartialAreaCode() {
        #expect(PhoneFormatter.format("6") == "(6")
        #expect(PhoneFormatter.format("646") == "(646")
    }

    @Test("4-6 digits show area code and prefix", arguments: zip(
        ["6469", "64694", "646946"],
        ["(646) 9", "(646) 94", "(646) 946"]
    ))
    func formatMidRange(input: String, expected: String) {
        #expect(PhoneFormatter.format(input) == expected)
    }

    @Test("10 digits produce full (XXX) XXX-XXXX format")
    func formatFull() {
        #expect(PhoneFormatter.format("6469466861") == "(646) 946-6861")
    }

    @Test("non-digit characters are stripped before formatting")
    func formatStripsNonDigits() {
        #expect(PhoneFormatter.format("(646) 946-6861") == "(646) 946-6861")
        #expect(PhoneFormatter.format("646.946.6861") == "(646) 946-6861")
    }

    @Test("input beyond 10 digits is capped")
    func formatCapsAt10() {
        #expect(PhoneFormatter.format("64694668619999") == "(646) 946-6861")
    }

    // MARK: - formatWithCountryCode

    @Test("empty digits returns empty")
    func formatCCEmpty() {
        #expect(PhoneFormatter.formatWithCountryCode("") == "")
    }

    @Test("partial digits include +1 prefix")
    func formatCCPartial() {
        #expect(PhoneFormatter.formatWithCountryCode("646") == "+1 (646")
        #expect(PhoneFormatter.formatWithCountryCode("64694") == "+1 (646) 94")
    }

    @Test("10 digits produce +1 (XXX) XXX-XXXX format")
    func formatCCFull() {
        #expect(PhoneFormatter.formatWithCountryCode("6469466861") == "+1 (646) 946-6861")
    }

    // MARK: - toE164

    @Test("10 raw digits normalise to E.164")
    func toE164FromRaw() {
        #expect(PhoneFormatter.toE164("6469466861") == "+16469466861")
    }

    @Test("+1-prefixed formatted input normalises correctly")
    func toE164FromFormatted() {
        #expect(PhoneFormatter.toE164("+1 (646) 946-6861") == "+16469466861")
        #expect(PhoneFormatter.toE164("+16469466861") == "+16469466861")
    }

    @Test("fewer than 10 digits returns nil")
    func toE164TooShort() {
        #expect(PhoneFormatter.toE164("64694") == nil)
        #expect(PhoneFormatter.toE164("") == nil)
    }
}
