import CADCore

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
        var encoder = try PortableSourceEncoder(limits: encodingLimits)
        try encoder.value(PortableDocumentSourcePayload(document: document))
        let bytes = encoder.bytes
        let tailBlocks = bytes.count % 64 < 56 ? 1 : 2
        let blockCount = bytes.count / 64 + tailBlocks
        let (blockWork, overflow) = blockCount.multipliedReportingOverflow(by: 136)
        let (inputWork, inputOverflow) = bytes.count.addingReportingOverflow(192)
        guard !overflow, !inputOverflow else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Source SHA-256 work.")
        }
        // The same allowance pays source byte reads, schedule expansion, compression,
        // state folding, initialized tail storage and final hexadecimal publication.
        try encoder.charge(work: inputWork)
        try encoder.charge(work: blockWork)
        return CADDocumentSourceFingerprint(
            algorithm: "sha256-cad-source-binary-v1",
            value: try SHA256Digest.sourceHexDigest(for: bytes)
        )
    }
}
