import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SubshapeGeometrySignature`.
extension CADIR.SubshapeGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .body(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "body", values: 1)
            try encoder.field("_0", value0)
        case let .vertex(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "vertex", values: 1)
            try encoder.field("_0", value0)
        case let .edge(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "edge", values: 1)
            try encoder.field("_0", value0)
        case let .face(value0):
            try encoder.enumeration("CADIR.SubshapeGeometrySignature", caseName: "face", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
