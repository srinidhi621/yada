import Foundation

struct YadaError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
