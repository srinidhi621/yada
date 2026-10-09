import Foundation

// Warning signals are not a claim of semantic equivalence. Every model result is reviewed.
enum FormatReview {
    private static let numbers = try! NSRegularExpression(pattern: #"\p{N}+(?:[.,:/-]\p{N}+)*"#)

    static func warning(original: String, formatted: String) -> String {
        func values(_ text: String) -> [String] {
            let string = text as NSString
            return numbers.matches(in: text, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }.sorted()
        }
        if values(original) != values(formatted) { return "Numbers may have changed. Compare with Raw before using this text." }
        return "Review names, facts, dates and meaning against Raw. The model can make mistakes."
    }
}
