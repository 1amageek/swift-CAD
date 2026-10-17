import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtrudeDirection`.
extension CADIR.ExtrudeDirection: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .normal:
            try encoder.enumeration("CADIR.ExtrudeDirection", caseName: "normal", values: 0, using: &admission)
        case let .vector(value0):
            try encoder.enumeration("CADIR.ExtrudeDirection", caseName: "vector", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case .symmetric:
            try encoder.enumeration("CADIR.ExtrudeDirection", caseName: "symmetric", values: 0, using: &admission)
        }
    }
}
