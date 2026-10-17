import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveCenterReference`.
extension CADIR.CurveCenterReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveCenterReference", fields: 1, using: &admission)
        try encoder.field("curve", curve, using: &admission)
    }
}
