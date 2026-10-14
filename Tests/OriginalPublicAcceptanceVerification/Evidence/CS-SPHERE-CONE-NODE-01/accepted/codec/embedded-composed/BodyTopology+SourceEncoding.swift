import CADCore
import CADTopology

/// Encodes original source fields owned by `CADTopology.BodyTopology`.
extension CADTopology.BodyTopology: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .solid(value0):
            try encoder.enumeration("CADTopology.BodyTopology", caseName: "solid", values: 1)
            try encoder.field("_0", value0)
        case let .sheet(value0):
            try encoder.enumeration("CADTopology.BodyTopology", caseName: "sheet", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
