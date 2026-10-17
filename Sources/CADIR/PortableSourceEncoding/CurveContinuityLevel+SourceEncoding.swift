import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveContinuityLevel`.
extension CADIR.CurveContinuityLevel: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.CurveContinuityLevel", caseName: "raw", values: 1, using: &admission)
        try encoder.field("rawValue", rawValue, using: &admission)
    }
}
