import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtractSelection`.
extension CADIR.ExtractSelection: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .component(value0, value1):
            try encoder.enumeration("CADIR.ExtractSelection", caseName: "component", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .faces(value0):
            try encoder.enumeration("CADIR.ExtractSelection", caseName: "faces", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .solidFaces(value0):
            try encoder.enumeration("CADIR.ExtractSelection", caseName: "solidFaces", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
