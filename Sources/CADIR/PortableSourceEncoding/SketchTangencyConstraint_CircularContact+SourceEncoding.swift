import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchTangencyConstraint.CircularContact`.
extension CADIR.SketchTangencyConstraint.CircularContact: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SketchTangencyConstraint.CircularContact", caseName: rawValue, values: 0, using: &admission)
    }
}
