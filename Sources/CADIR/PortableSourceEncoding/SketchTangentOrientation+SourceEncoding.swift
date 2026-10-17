import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchTangentOrientation`.
extension CADIR.SketchTangentOrientation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SketchTangentOrientation", caseName: rawValue, values: 0, using: &admission)
    }
}
