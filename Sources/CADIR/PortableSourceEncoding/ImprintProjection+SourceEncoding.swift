import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintProjection`.
extension CADIR.ImprintProjection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .normal:
            try encoder.enumeration("CADIR.ImprintProjection", caseName: "normal", values: 0)
        case let .vector(value0, value1, value2):
            try encoder.enumeration("CADIR.ImprintProjection", caseName: "vector", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        }
    }
}
