import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepGuideMethod`.
extension CADIR.SweepGuideMethod: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SweepGuideMethod", caseName: rawValue, values: 0)
    }
}
