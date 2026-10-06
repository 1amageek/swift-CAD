import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchPlane`.
extension CADIR.SketchPlane: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .xy:
            try encoder.enumeration("CADIR.SketchPlane", caseName: "xy", values: 0)
        case .yz:
            try encoder.enumeration("CADIR.SketchPlane", caseName: "yz", values: 0)
        case .zx:
            try encoder.enumeration("CADIR.SketchPlane", caseName: "zx", values: 0)
        case let .plane(value0):
            try encoder.enumeration("CADIR.SketchPlane", caseName: "plane", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
