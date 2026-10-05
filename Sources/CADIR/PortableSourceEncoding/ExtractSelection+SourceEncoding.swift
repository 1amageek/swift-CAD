import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtractSelection`.
extension CADIR.ExtractSelection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .component(value0, value1):
            try encoder.enumeration("CADIR.ExtractSelection", caseName: "component", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .faces(value0):
            try encoder.enumeration("CADIR.ExtractSelection", caseName: "faces", values: 1)
            try encoder.field("_0", value0)
        case let .solidFaces(value0):
            try encoder.enumeration("CADIR.ExtractSelection", caseName: "solidFaces", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
