import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareFitOptions.BoundaryFlow`.
extension CADIR.SquareFitOptions.BoundaryFlow: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SquareFitOptions.BoundaryFlow", caseName: rawValue, values: 0)
    }
}
