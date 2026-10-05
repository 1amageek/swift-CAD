import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeProductAssociation`.
extension CADIR.IndependentShapeProductAssociation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeProductAssociation", fields: 2)
        try encoder.field("definitionID", definitionID)
        try encoder.field("representationID", representationID)
    }
}
