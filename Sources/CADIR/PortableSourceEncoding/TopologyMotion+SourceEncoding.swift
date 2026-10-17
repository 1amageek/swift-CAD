import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TopologyMotion`.
extension CADIR.TopologyMotion: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .translation(value0):
            try encoder.enumeration("CADIR.TopologyMotion", caseName: "translation", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .rotation(value0):
            try encoder.enumeration("CADIR.TopologyMotion", caseName: "rotation", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .scale(value0):
            try encoder.enumeration("CADIR.TopologyMotion", caseName: "scale", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
