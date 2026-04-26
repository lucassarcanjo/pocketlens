import Foundation
import CryptoKit

/// File-byte hashing helpers used for import-batch dedup
/// (`import_batches.source_file_sha256` UNIQUE).
public enum FileHash {
    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return sha256(of: data)
    }

    public static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
