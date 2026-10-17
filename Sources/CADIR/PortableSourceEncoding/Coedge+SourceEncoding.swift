import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Coedge`.
extension CADTopology.Coedge: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Coedge", fields: 3, using: &admission)
        try encoder.field("edgeID", edgeID, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
        try encoder.field("surfaceParameterCurve", surfaceParameterCurve, using: &admission)
    }
}
