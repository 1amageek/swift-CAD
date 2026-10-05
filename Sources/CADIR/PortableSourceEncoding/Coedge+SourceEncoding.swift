import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Coedge`.
extension CADTopology.Coedge: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Coedge", fields: 3)
        try encoder.field("edgeID", edgeID)
        try encoder.field("orientation", orientation)
        try encoder.field("surfaceParameterCurve", surfaceParameterCurve)
    }
}
