import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareFitOptions.BoundaryFlow`.
extension CADIR.SquareFitOptions.BoundaryFlow: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SquareFitOptions.BoundaryFlow", caseName: rawValue, values: 0, using: &admission)
    }
}
