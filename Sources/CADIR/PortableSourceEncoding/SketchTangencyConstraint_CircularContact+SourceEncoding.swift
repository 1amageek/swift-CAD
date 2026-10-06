import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchTangencyConstraint.CircularContact`.
extension CADIR.SketchTangencyConstraint.CircularContact: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SketchTangencyConstraint.CircularContact", caseName: rawValue, values: 0)
    }
}
