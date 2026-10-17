import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchPlane`.
extension CADIR.SketchPlane: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .xy:
            try encoder.enumeration("CADIR.SketchPlane", caseName: "xy", values: 0, using: &admission)
        case .yz:
            try encoder.enumeration("CADIR.SketchPlane", caseName: "yz", values: 0, using: &admission)
        case .zx:
            try encoder.enumeration("CADIR.SketchPlane", caseName: "zx", values: 0, using: &admission)
        case let .plane(value0):
            try encoder.enumeration("CADIR.SketchPlane", caseName: "plane", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
