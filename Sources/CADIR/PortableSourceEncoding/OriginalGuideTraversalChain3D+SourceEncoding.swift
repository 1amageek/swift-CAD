import CADCore
import CADGeometry

/// Retains the declared exact aggregate chart and original guide source order.
extension CADGeometry.OriginalGuideTraversalChain3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalGuideTraversalChain3D", fields: 3, using: &admission)
        try encoder.field("sourceSegmentOrdinals", sourceSegmentOrdinals, using: &admission)
        try encoder.field("stations", stations, using: &admission)
        try encoder.field("traversals", traversals, using: &admission)
    }
}
