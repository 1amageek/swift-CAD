import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BRepRepairAction`.
extension CADTopology.BRepRepairAction: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADTopology.BRepRepairAction", caseName: rawValue, values: 0)
    }
}
