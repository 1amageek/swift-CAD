import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSplineEndpointReference`.
extension CADIR.SketchSplineEndpointReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchSplineEndpointReference", fields: 2, using: &admission)
        try encoder.field("endpoint", endpoint, using: &admission)
        try encoder.field("splineID", splineID, using: &admission)
    }
}
