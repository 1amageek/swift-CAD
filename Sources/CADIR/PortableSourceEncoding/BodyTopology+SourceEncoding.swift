import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BodyTopology`.
extension CADTopology.BodyTopology: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .solid(value0):
            try encoder.enumeration("CADTopology.BodyTopology", caseName: "solid", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sheet(value0):
            try encoder.enumeration("CADTopology.BodyTopology", caseName: "sheet", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
