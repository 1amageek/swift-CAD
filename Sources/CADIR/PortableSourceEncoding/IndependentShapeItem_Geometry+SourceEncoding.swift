import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeItem.Geometry`.
extension CADIR.IndependentShapeItem.Geometry: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .curve(value0, value1):
            try encoder.enumeration("CADIR.IndependentShapeItem.Geometry", caseName: "curve", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .surface(value0):
            try encoder.enumeration("CADIR.IndependentShapeItem.Geometry", caseName: "surface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
