import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtrudeDirection`.
extension CADIR.ExtrudeDirection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .normal:
            try encoder.enumeration("CADIR.ExtrudeDirection", caseName: "normal", values: 0)
        case let .vector(value0):
            try encoder.enumeration("CADIR.ExtrudeDirection", caseName: "vector", values: 1)
            try encoder.field("_0", value0)
        case .symmetric:
            try encoder.enumeration("CADIR.ExtrudeDirection", caseName: "symmetric", values: 0)
        }
    }
}
