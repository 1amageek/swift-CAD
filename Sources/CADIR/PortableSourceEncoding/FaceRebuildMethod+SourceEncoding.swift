import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceRebuildMethod`.
extension CADIR.FaceRebuildMethod: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .explicit(value0):
            try encoder.enumeration("CADIR.FaceRebuildMethod", caseName: "explicit", values: 1)
            try encoder.field("_0", value0)
        case let .tolerance(value0):
            try encoder.enumeration("CADIR.FaceRebuildMethod", caseName: "tolerance", values: 1)
            try encoder.field("_0", value0)
        case .nominal:
            try encoder.enumeration("CADIR.FaceRebuildMethod", caseName: "nominal", values: 0)
        case let .square(value0):
            try encoder.enumeration("CADIR.FaceRebuildMethod", caseName: "square", values: 1)
            try encoder.field("_0", value0)
        case let .given(value0):
            try encoder.enumeration("CADIR.FaceRebuildMethod", caseName: "given", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
