import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductDimension`.
extension CADIR.ProductDimension: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductDimension", fields: 9, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("lowerDeviation", lowerDeviation, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("nominal", nominal, using: &admission)
        try encoder.field("referenceTarget", referenceTarget, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("upperDeviation", upperDeviation, using: &admission)
    }
}
