import CADCore
import CADGeometry

/// Retains the declared exact aggregate chart and original guide source order.
extension CADGeometry.OriginalGuideTraversalChain3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalGuideTraversalChain3D", fields: 3)
        try encoder.field("sourceSegmentOrdinals", sourceSegmentOrdinals)
        try encoder.field("stations", stations)
        try encoder.field("traversals", traversals)
    }
}
