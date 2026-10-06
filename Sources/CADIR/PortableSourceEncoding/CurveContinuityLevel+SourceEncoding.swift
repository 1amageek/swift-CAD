import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveContinuityLevel`.
extension CADIR.CurveContinuityLevel: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.CurveContinuityLevel", caseName: "raw", values: 1)
        try encoder.field("rawValue", rawValue)
    }
}
