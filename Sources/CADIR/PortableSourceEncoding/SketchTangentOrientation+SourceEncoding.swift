import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchTangentOrientation`.
extension CADIR.SketchTangentOrientation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SketchTangentOrientation", caseName: rawValue, values: 0)
    }
}
