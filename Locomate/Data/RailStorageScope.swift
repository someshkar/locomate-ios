import CryptoKit
import Foundation

/// Keeps private run caches, journey plans, Passport entries, and sessions
/// separate when a development build changes its gateway origin.
enum RailStorageScope {
    static func gateway(_ baseURL: URL) -> String {
        let canonical = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
