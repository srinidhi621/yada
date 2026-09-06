import Foundation

struct YadaError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

@main
struct FormattingProbe {
    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, let style = TextMode(rawValue: arguments[1]), style.requiresReview else { exit(2) }
        let start = ContinuousClock.now
        var result: [String: Any] = ["style": arguments[1], "locale": arguments[2], "input": arguments[3]]
        do {
            result["output"] = try await LocalFormatter().format(arguments[3], style: style, locale: Locale(identifier: arguments[2]))
        } catch {
            result["error"] = (error as? YadaError)?.message ?? String(describing: error)
        }
        let duration = start.duration(to: .now).components
        result["milliseconds"] = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
