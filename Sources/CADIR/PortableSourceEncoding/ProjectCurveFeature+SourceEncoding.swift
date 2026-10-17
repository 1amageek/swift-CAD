import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProjectCurveFeature`.
extension CADIR.ProjectCurveFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProjectCurveFeature", fields: 4, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("planeNormal", planeNormal, using: &admission)
        try encoder.field("planeOrigin", planeOrigin, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
