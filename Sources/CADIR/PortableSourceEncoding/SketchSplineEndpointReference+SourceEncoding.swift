import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSplineEndpointReference`.
extension CADIR.SketchSplineEndpointReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchSplineEndpointReference", fields: 2)
        try encoder.field("endpoint", endpoint)
        try encoder.field("splineID", splineID)
    }
}
