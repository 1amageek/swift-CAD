import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TopologyMotion`.
extension CADIR.TopologyMotion: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .translation(value0):
            try encoder.enumeration("CADIR.TopologyMotion", caseName: "translation", values: 1)
            try encoder.field("_0", value0)
        case let .rotation(value0):
            try encoder.enumeration("CADIR.TopologyMotion", caseName: "rotation", values: 1)
            try encoder.field("_0", value0)
        case let .scale(value0):
            try encoder.enumeration("CADIR.TopologyMotion", caseName: "scale", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
