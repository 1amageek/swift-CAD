import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletShape`.
extension CADIR.FilletShape: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.FilletShape", caseName: rawValue, values: 0)
    }
}
