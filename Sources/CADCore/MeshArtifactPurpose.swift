/// The caller-defined purpose a Mesh artifact was produced for.
///
/// The kernel never interprets the value. It exists so an artifact produced for
/// one consumer's purpose is never handed to a request carrying another, which
/// neither the source fingerprint nor the tessellation fidelity can express on
/// its own: two purposes can legitimately request the same fidelity from the
/// same source and still must not share one artifact's resource accounting.
public struct MeshArtifactPurpose: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The purpose of a request that declares none.
    ///
    /// Artifacts recorded under this purpose are shared among every caller that
    /// declares no purpose. A consumer whose artifacts must not be shared
    /// declares its own purpose instead of relying on this value.
    public static let unspecified = MeshArtifactPurpose(rawValue: "unspecified")

    /// Rejects a purpose that cannot identify a consumer.
    public func validate() throws {
        guard !rawValue.isEmpty else {
            throw MeshArtifactPurposeError.emptyPurpose
        }
        guard rawValue.allSatisfy({ !$0.isWhitespace }) else {
            throw MeshArtifactPurposeError.whitespaceInPurpose(rawValue)
        }
    }
}

/// A supplied `MeshArtifactPurpose` cannot identify a consumer.
public enum MeshArtifactPurposeError: Error, Equatable, Sendable {
    case emptyPurpose
    case whitespaceInPurpose(String)
}
