import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintProjection`.
extension CADIR.ImprintProjection: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .normal:
            try encoder.enumeration("CADIR.ImprintProjection", caseName: "normal", values: 0, using: &admission)
        case let .vector(value0, value1, value2):
            try encoder.enumeration("CADIR.ImprintProjection", caseName: "vector", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        }
    }
}
