import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimKnotReference`.
extension CADIR.SurfaceTrimKnotReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceTrimKnotReference", fields: 2, using: &admission)
        try encoder.field("knotIndex", knotIndex, using: &admission)
        try encoder.field("trim", trim, using: &admission)
    }
}
