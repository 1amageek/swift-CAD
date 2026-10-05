import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductDimension`.
extension CADIR.ProductDimension: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductDimension", fields: 9)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("kind", kind)
        try encoder.field("lowerDeviation", lowerDeviation)
        try encoder.field("name", name)
        try encoder.field("nominal", nominal)
        try encoder.field("referenceTarget", referenceTarget)
        try encoder.field("target", target)
        try encoder.field("upperDeviation", upperDeviation)
    }
}
