import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceLoopOffsetSide`.
extension CADIR.FaceLoopOffsetSide: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.FaceLoopOffsetSide", caseName: rawValue, values: 0)
    }
}
