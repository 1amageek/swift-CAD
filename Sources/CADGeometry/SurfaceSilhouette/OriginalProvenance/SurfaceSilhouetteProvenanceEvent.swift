/// Typed framing of a complete original silhouette source; no sampled geometry.
public enum SurfaceSilhouetteProvenanceEvent: Sendable {
    case beginRecord(type: String)
    case endRecord
    case field(String)
    case beginArray(count: Int)
    case endArray
    case text(String)
    case boolean(Bool)
    case integer(Int)
    case floatingBits(UInt64)
    case unsignedWords([UInt32])
    case surface(Surface3D)
    case null
}
