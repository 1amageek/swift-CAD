import CADCore
import CADGeometry

public struct CADDocumentSourceFingerprint: Hashable, Sendable {
    public var algorithm: String
    public var value: String

    public init(algorithm: String, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

#if !hasFeature(Embedded)
extension CADDocumentSourceFingerprint: Codable {}
#endif

public extension CADDocument {
    func sourceFingerprint(tolerance: ModelingTolerance) throws -> CADDocumentSourceFingerprint {
        try ValidatedCADDocument(self, tolerance: tolerance).sourceFingerprint()
    }

    func sourceFingerprint(tolerance: ModelingTolerance, encodingLimits: PortableSourceEncodingLimits) throws -> CADDocumentSourceFingerprint {
        try ValidatedCADDocument(self, tolerance: tolerance).sourceFingerprint(encodingLimits: encodingLimits)
    }

    func sourceFingerprint(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> CADDocumentSourceFingerprint {
        try sourceFingerprint(tolerance: tolerance, encodingLimits: PortableDocumentSourcePayload.defaultLimits,
            using: &execution)
    }

    func sourceFingerprint(tolerance: ModelingTolerance, encodingLimits: PortableSourceEncodingLimits,
        using execution: inout OriginalQueryExecution) throws -> CADDocumentSourceFingerprint {
        let validated = try ValidatedCADDocument(self, tolerance: tolerance, using: &execution)
        return try validated.sourceFingerprint(encodingLimits: encodingLimits, using: &execution)
    }
}

public extension ValidatedCADDocument {
    /// Copies share this immutable document's completed source identity. Computation is outside the mutex.
    func sourceFingerprint() throws -> CADDocumentSourceFingerprint {
        try sourceFingerprintMemo.value {
            try sourceFingerprint(encodingLimits: PortableDocumentSourcePayload.defaultLimits)
        }
    }

    /// Explicit allowances always admit this invocation; a cache does not waive a smaller caller budget.
    func sourceFingerprint(encodingLimits: PortableSourceEncodingLimits) throws -> CADDocumentSourceFingerprint {
        var admission = UnboundedAuthoringAdmission()
        return try sourceFingerprint(encodingLimits: encodingLimits, using: &admission)
    }

    /// An explicit caller always pays its own traversal, even when the ordinary memo is warm.
    func sourceFingerprint<A: NumericWorkAdmission & ~Copyable>(
        using admission: inout A) throws -> CADDocumentSourceFingerprint {
        try sourceFingerprint(encodingLimits: PortableDocumentSourcePayload.defaultLimits, using: &admission)
    }

    func sourceFingerprint<A: NumericWorkAdmission & ~Copyable>(encodingLimits: PortableSourceEncodingLimits,
        using admission: inout A) throws -> CADDocumentSourceFingerprint {
        try admission.checkpoint()
        var encoder = try PortableSourceEncoder(limits: encodingLimits)
        try encoder.value(PortableDocumentSourcePayload(document: document), using: &admission)
        let bytes = encoder.bytes
        let digest = try SHA256Digest.sourceHexDigest(for: bytes, encoding: &encoder, using: &admission)
        try admission.retainStorage(count: 1, stride: MemoryLayout<CADDocumentSourceFingerprint>.stride)
        let result = CADDocumentSourceFingerprint(algorithm: "sha256-cad-source-binary-v1", value: digest)
        try admission.checkpoint()
        return result
    }
}
