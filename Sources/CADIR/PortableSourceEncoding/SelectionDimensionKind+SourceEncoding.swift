import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SelectionDimensionKind`.
extension CADIR.SelectionDimensionKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SelectionDimensionKind", caseName: rawValue, values: 0)
    }
}
