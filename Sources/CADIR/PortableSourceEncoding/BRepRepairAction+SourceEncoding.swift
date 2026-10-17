import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BRepRepairAction`.
extension CADTopology.BRepRepairAction: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADTopology.BRepRepairAction", caseName: rawValue, values: 0, using: &admission)
    }
}
