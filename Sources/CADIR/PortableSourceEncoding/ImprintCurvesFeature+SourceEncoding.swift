import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintCurvesFeature`.
extension CADIR.ImprintCurvesFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ImprintCurvesFeature", fields: 4)
        try encoder.field("completion", completion)
        try encoder.field("curves", curves)
        try encoder.field("projection", projection)
        try encoder.field("target", target)
    }
}
