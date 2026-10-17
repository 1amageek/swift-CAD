import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeProductAssociation`.
extension CADIR.IndependentShapeProductAssociation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeProductAssociation", fields: 2, using: &admission)
        try encoder.field("definitionID", definitionID, using: &admission)
        try encoder.field("representationID", representationID, using: &admission)
    }
}
