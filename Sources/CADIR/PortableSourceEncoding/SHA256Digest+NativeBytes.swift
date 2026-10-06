#if !hasFeature(Embedded)
import Foundation

extension SHA256Digest {
    static func hexDigest(for data: Data) -> String {
        data.withUnsafeBytes { hexDigest(of: $0) }
    }
}
#endif
