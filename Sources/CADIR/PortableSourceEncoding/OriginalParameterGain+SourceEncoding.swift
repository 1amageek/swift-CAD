import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalParameterGain`.
extension CADGeometry.OriginalParameterGain: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .binary(value0):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "binary", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .ratio(value0, value1):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "ratio", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .difference(value0):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "difference", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .product(value0):
            try encoder.enumeration("CADGeometry.OriginalParameterGain", caseName: "product", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
