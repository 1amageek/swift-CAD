#if !hasFeature(Embedded)
import Foundation

extension SHA256Digest {
    static func hexDigest(for data: Data) throws -> String {
        try data.withUnsafeBytes { try hexDigest(of: $0) }
    }
}
#endif
