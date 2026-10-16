#if !hasFeature(Embedded)
import CADCore
import CADGeometry

/// Native canonical text adapter for immutable original STEP record identities.
package enum OriginalSTEPIdentityCoding {
    static func decode(from decoder: Decoder) throws -> PortableIdentity128 {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        var allowance = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        try allowance.consumeWork(37)
        guard text.utf8.prefix(37).count == 36 else {
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Original STEP identity requires exactly 36 UTF-8 bytes.")
        }
        // Core's parser owns a 36-byte UTF-8 array and a 16-byte octet buffer.
        let bytes = 36.addingReportingOverflow(16)
        guard !bytes.overflow else {
            throw IndependentShapeSourceError.resourceLimitExceeded("Original identity parser storage overflow.")
        }
        let stride = MemoryLayout<UInt32>.stride
        let words = bytes.partialValue / stride + (bytes.partialValue % stride == 0 ? 0 : 1)
        try RationalAlgebraStorage.retain(words, of: UInt32.self, usage: &allowance)
        try allowance.consumeWork(36 + 36 + 16)
        do {
            let identity = try PortableIdentity128(canonicalString: text)
            try allowance.consumeWork(0)
            return identity
        } catch PortableIdentityError.invalidCanonicalString {
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Invalid UUID string for original STEP identity.")
        }
    }
}
#endif
