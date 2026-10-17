import CADCore
import CADGeometry
import CADTopology

/// Encodes the actual STEP GROUP owner independently of its assignments.
extension IndependentShapeSTEPGroup: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeSTEPGroup", fields: 3, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}
