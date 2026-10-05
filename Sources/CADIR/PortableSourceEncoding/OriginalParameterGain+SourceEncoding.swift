import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalParameterGain`.
extension CADGeometry.OriginalParameterGain: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .binary(value0):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "binary", values: 1)
            try encoder.field("_0", value0)
        case let .ratio(value0, value1):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "ratio", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .difference(value0):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "difference", values: 1)
            try encoder.field("_0", value0)
        case let .product(value0):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "product", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
