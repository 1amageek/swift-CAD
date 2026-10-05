import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveFrameOrientation`.
extension CADIR.CurveFrameOrientation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.CurveFrameOrientation", caseName: rawValue, values: 0)
    }
}
