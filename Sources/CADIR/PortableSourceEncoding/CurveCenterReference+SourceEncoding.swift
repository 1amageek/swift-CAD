import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveCenterReference`.
extension CADIR.CurveCenterReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveCenterReference", fields: 1)
        try encoder.field("curve", curve)
    }
}
