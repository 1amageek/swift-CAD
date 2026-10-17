import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SubshapeGeometrySignature`.
extension CADIR.SubshapeGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .body(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "body", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .vertex(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "vertex", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .edge(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "edge", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .face(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "face", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
