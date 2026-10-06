import CADCore
import CADGeometry
import CADTopology

/// Encodes the actual STEP GROUP owner independently of its assignments.
extension IndependentShapeSTEPGroup: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeSTEPGroup", fields: 3)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("name", name)
    }
}
