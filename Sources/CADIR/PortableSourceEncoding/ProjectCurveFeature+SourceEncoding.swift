import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProjectCurveFeature`.
extension CADIR.ProjectCurveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProjectCurveFeature", fields: 4)
        try encoder.field("direction", direction)
        try encoder.field("planeNormal", planeNormal)
        try encoder.field("planeOrigin", planeOrigin)
        try encoder.field("source", source)
    }
}
